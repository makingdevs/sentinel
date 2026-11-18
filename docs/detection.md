# Detección de personas y autos

En `/cameras`, cada tarjeta permite escoger **Desactivado**, **Python · YOLO** o **Elixir · ONNX**. El cambio afecta esa tarjeta; dos espectadores de la misma cámara/calidad/motor comparten el procesamiento. Cambiar de calidad conserva el motor. **Reintentar** vuelve a abrir el reproductor y permite recuperar un detector que agotó sus reintentos.

Ambos motores usan YOLO11n COCO y filtran exclusivamente `person=0` y `car=2`. Autobuses, camiones, bicicletas y motos no se incluyen como autos. Las cajas incluyen clase y confianza; son detecciones por fotograma, no identificación de personas, seguimiento ni conteos únicos.

## Instalación local

Requisitos comprobados en esta máquina: macOS arm64, Python 3.12, Elixir 1.19/OTP 26, Rust/Cargo y herramientas de compilación de Xcode. Las bibliotecas de FFmpeg, libvips y XLA se descargan durante el build. El FFmpeg de línea de comandos se utiliza para preparar/exportar pruebas, no para procesar el RTSP de producción. PostgreSQL local se necesita para arrancar Sentinel y ejecutar su suite habitual.

```bash
bash scripts/detection/setup.sh
npm ci --prefix assets
mix assets.build
bash scripts/detection/server.sh
```

El script crea `.venv`, instala el lock Python con hashes, verifica SHA256 del peso original, exporta ONNX estático opset17 a 640px y guarda `models/manifest.json`. Los pesos, el entorno y las salidas temporales están ignorados por Git. El script contiene las opciones CXX necesarias para compilar EXLA 0.9.2 con el Xcode de esta máquina; no modifica dependencias descargadas ni instala paquetes globales.

Si `mix compile` falla al compilar EXLA en macOS con errores de C++ como `missing-template-arg-list-after-template-kw` o `invalid-specialization`, recompila esa dependencia con las opciones que usa el script:

```bash
CXX='c++ -Wno-missing-template-arg-list-after-template-kw -Wno-invalid-specialization' mix deps.compile exla --force
mix compile
```

Las comillas hacen que `CXX` incluya tanto el compilador como sus opciones. El primer comando fuerza la recompilación de EXLA; el segundo continúa la compilación de la aplicación.

`server.sh` utiliza el puerto 4013 por defecto. Cambiarlo con `PORT`. Las fuentes se leen desde `CAMERA_RTSP_SOURCES_FILE` (por defecto `tmp/camera_rtsp_sources.json`), con la misma configuración privada del monitoreo existente. Las credenciales RTSP no se envían al navegador.

Variables de ubicación opcionales:

- `DETECTION_PYTHON`: ruta absoluta al Python del entorno.
- `DETECTION_MODEL_DIRECTORY`: directorio que contiene `yolo11n.pt` y `yolo11n.onnx`.
- `DETECTION_WORKER_SCRIPT`: ruta absoluta a `python/worker.py`.

Para un release, distribuir explícitamente el worker y su entorno Python, los modelos y estas rutas; los archivos del directorio de desarrollo no se incorporan automáticamente al release.

## Procesamiento y límites

```text
RTSP/H264 o H265 → parser/decoder → RGB a 640px de ancho
  → filtro de inferencia → dibujado común → I420 → H264 → HLS
```

Desactivado conserva el remux RTSP→HLS original. Activado recodifica, por lo que consume más CPU. Ambos motores cargan el modelo una vez por stream y usan CPU. Python utiliza PyTorch con dos threads; Elixir utiliza Ortex con los threads por defecto de ONNX Runtime y EXLA para pre/postproceso. Las mediciones comparan estas configuraciones prácticas; no representan una comparación con idéntico presupuesto de threads ni con GPU.

El renderer rasteriza las etiquetas en una capa SVG una sola vez por resultado y reutiliza esa capa; no guarda píxeles de video anteriores. Una frontera de flujo conserva un solo fotograma RGB pendiente, y las demandas posteriores se limitan a uno para evitar acumular video si el dibujado/encoder se saturan. Se descartan frames antes de acumular retraso.

El filtro envía como máximo una inferencia simultánea y retiene un solo fotograma pendiente reemplazable. El objetivo inicial es una inferencia cada 200ms; el video puede seguir a 25FPS reutilizando cajas recientes. **Las cajas pueden corresponder a un fotograma anterior**, con un límite de 500ms tanto de reloj local como de PTS; se eliminan al caducar. Si una inferencia tarda más que ese límite, aparece el estado saturado y puede verse video sin cajas. No se dibujan resultados antiguos sobre una generación nueva.

El supervisor limita los detectores a ocho. Un cambio de motor/calidad deja el stream anterior disponible para otros espectadores; si ya nadie lo consume, el timeout existente de 60s libera sus recursos. Durante esa transición puede alcanzarse temporalmente el límite. La recuperación usa hasta tres reintentos con espera creciente; el usuario también puede pulsar Reintentar. Los estados de la insignia son actuales, mientras que HLS conserva su retraso habitual de varios segundos.

La IPC Python usa un proceso persistente sin shell, paquetes de longitud acotada y RGB binario; stdout queda reservado al protocolo. Al cerrar el propietario se cierra el puerto y Python recibe EOF. Los buffers se limitan a 1280×1280; el conversor mantiene proporción con ancho 640. Los videos extremadamente verticales que excedan el límite fallan explícitamente.

## Verificación y comparación

```bash
mix test test/sentinel/detection test/sentinel_web/live/detection_live_test.exs
.venv/bin/python -m pytest python/tests
node --test assets/js/hooks/hls_player.test.mjs
bash scripts/detection/smoke.sh
bash scripts/detection/benchmark.sh
mix precommit
```

`smoke.sh` conecta la primera cámara configurada, calidad secundaria, y prueba cada motor 35s. Opciones: `DETECTION_CAMERA`, `DETECTION_QUALITY`; se pueden pasar motores como argumentos, por ejemplo `bash scripts/detection/smoke.sh python elixir`. Usa archivos de salida temporales, sin modificar la configuración de las cámaras.

El benchmark usa `Superior.mp4` del taller, convertido una sola vez a 640px/25FPS y reproducido al mismo ritmo en cada pipeline. Se puede indicar `DETECTION_WORKSHOP_DIRECTORY`; de lo contrario busca el taller en `~/Downloads`. La ejecución predeterminada usa `MIX_ENV=prod` y no arranca el endpoint ni el Repo. Es serial: 1/4/8 streams, original/Python/Elixir, tres repeticiones, 10s de calentamiento y 60s de medición por caso. Tarda aproximadamente 32 minutos, más instalación y preparación. No ejecutar otros procesos pesados durante la medición. La entrada del benchmark ya está a640px: una cámara RTSP de resolución principal mayor exige más decodificación y no queda representada por esa matriz. Empezar con calidad secundaria.

```bash
# Comprobación rápida, con resultados separados de la matriz definitiva:
bash scripts/detection/benchmark.sh --seconds 8 --repetitions 1 --counts 1 --output tmp/detection-benchmark-check
# H265: ruta de entrada alternativa con la misma salida H264 anotada:
DETECTION_FIXTURE_CODEC=H265 bash scripts/detection/benchmark.sh --seconds 8 --repetitions 1 --counts 1 --output tmp/detection-h265-check
```

El perfil aislado del dibujado se ejecuta con `bash scripts/detection/benchmark.sh --profile-render`. Compara la implementación original, SVG sin caché y SVG con caché.

Cada caso conserva `result.json`, `resources.json`, `run.log` y HLS en `tmp/detection-benchmark/`. El runner reanuda casos ya terminados y produce `summary.json`. RSS incluye BEAM y sus procesos descendientes; CPU puede superar 100% porque suma núcleos. `beam_memory_bytes` no incluye toda la memoria nativa: usar RSS para comparar consumo real. FPS de inferencia y FPS de video son métricas diferentes.

`pipeline_lag_p95_ms` mide el retraso desde el ritmo conocido del fixture hasta la salida codificada. **No incluye segmentación HLS, transporte HTTP ni reproducción en navegador**; no debe presentarse como latencia punta a punta. El tiempo extremo a extremo de una cámara requiere una referencia temporal visible en la escena o timestamps de captura verificables.

Se incluye una comprobación pequeña con anotaciones manuales (`python/sanity_annotations.json`, IoU≥0.5) para una imagen con cuatro peatones, una región frontal con autos y una escena cenital. Es una prueba de plausibilidad, no una estimación de precisión general. En la escena cenital, ambos motores omitieron los nueve autos anotados: este peso nano no basta para esa perspectiva sin evaluar otro modelo o ajuste específico. No interpretar igualdad entre motores como exactitud. El preprocessing usa interpoladores distintos (OpenCV frente a libvips) y el postproceso de YOLO puede redondear coordenadas, por lo que los resultados pueden diferir ligeramente aun usando los mismos pesos.

Fuentes: [notebook y evidencia del taller](../.claude/plans/personas-autos/research/evidencia.md), [Membrane YOLO demo](https://github.com/membraneframework/membrane_demo/tree/master/yolo), [YOLO Elixir](https://yolo.hexdocs.pm/readme.html). Los artefactos conservan la procedencia de Ultralytics; consultar su licencia junto con los pesos y el paquete utilizados.
