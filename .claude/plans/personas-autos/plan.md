# Personas y autos en video en vivo

Estado: propuesto. Profundidad: deep. Un plan, 5 fases, 15 tareas. Sin implementación automática.

## Objetivo y opciones
Detectar exclusivamente personas y autos en los streams que Sentinel ya reproduce y mostrar cajas, clase y confianza dentro del video. Selector por cámara: desactivado / Python / Elixir. Comparar ambos con datos reproducibles antes de recomendar el motor definitivo.

| Opción | Ventaja | Costo / incertidumbre |
|---|---|---|
| Python Ultralytics supervisado por Elixir | Reproduce directamente el notebook, referencia rápida | Entorno Python/PyTorch, IPC y copias de fotogramas |
| Elixir YOLO + Ortex | Integración con OTP y Membrane; inferencia ONNX | Compilación nativa, compatibilidad y precisión del export por comprobar |

Recomendación: implementar ambos por etapas, Python como referencia y Elixir como candidato; elegir por benchmark. Elixir también usa runtime nativo ONNX, no implica cómputo puro BEAM. Modelo inicial común: yolo11n, Python .pt y Elixir .onnx exportado del mismo peso; 640px, umbrales y NMS equivalentes. No comparar el YOLOX-L del demo con un nano. CPU como base verificable; aceleración como medición separada.

## Arquitectura y mapa de interacción
```
Cámara/RTSP → Monitoring.Stream (cámara, calidad, motor, generación)
  desactivado → pipeline comprimido actual → HLS → HlsPlayer
  activado → decoder H264/H265 → RGB/resize → coordinador acotado
             → adaptador Python | adaptador YOLO/Ortex
             → filtro persona/auto → renderer común → I420/encoder H264 → HLS
```
El contrato de detección incluye cámara, generación, frame_id, PTS, tamaño original, transformación resize/letterbox, motor, duración y lista {class_id, confidence, xyxy}. Las coordenadas se llevan al fotograma mostrado, se recortan y validan. El renderer común asegura cajas comparables. En Elixir, adaptar Detector/metadata y filtrar ANTES de Drawer; si no permite controlar modelo/colas/telemetría al nivel necesario, usar un filtro propio con YOLO.detect conservando el contrato. No suponer opción classes del plugin.

UI: seleccionar motor y activar/desactivar → reinserta tarjeta en stream → nueva URL/generación → cleanup del hook anterior → reproducción anotada. Cambiar calidad/reintentar/quitar invalida resultados pendientes. Mostrar calentando/activo/saturado/error y motor; estadísticas de inferencia son actuales y se identifican como tales, no conteos sincronizados con un HLS atrasado. Para conteos del fotograma, dibujarlos dentro del video.

Mantener HLS; WebRTC sería otro proyecto. Cajas quemadas requieren recodificar y aumentan CPU y latencia. No prometer FPS sin medir. Sin tracking, conteos de cruces, zonas, pose, nuevas tablas ni Oban en esta entrega.

## Fase 1 — Prueba de viabilidad
- [x] T1 [media] Resolver versiones en rama de trabajo conservando cambios existentes; verificar compatibilidad de membrane_yolo_plugin/YOLO/Ortex/Nx y plugins decoder/scale/encoder con mix.lock. Registrar versiones exactas y requisitos arm64; no copiar Mix.install del Livebook.
- [x] T2 [python] Crear `.venv`, requisitos fijados, descargar peso a directorio local ignorado y exportar ONNX estático sin NMS embebido si lo requiere YOLO. Registrar SHA256, opset, clases y licencia de artefactos. Probar una imagen en cada motor, comparar cajas y transformaciones. Verificar capacidades CPU/CoreML/MPS por separado.
- [x] T3 [media] Probar decode→RGB→encode→HLS con fixtures H264 y H265 y discontinuidad/reconexión. Confirmar el formato real de salida RTSP y entrada del SinkBin; no insertar un decoder asumiendo buffers ya parseados. Si H265 no es viable, documentar error accionable y opción H264 en cámara.

## Fase 2 — Contrato y referencia Python
- [x] T4 [otp] Crear `Sentinel.Detection` con behavior de adaptador y estructuras frame/result. Defaults configurables: clases [0,2], confidence 0.35, IoU 0.45, ancho 640, objetivo inicial 5 inferencias/s. Rechazar clases, dimensiones, NaN y payloads inválidos.
- [x] T5 [python] Crear worker persistente sin GUI, modelo cargado una vez, YOLO.predict(classes=[0,2]); supervisar con Port y ejecutable absoluto, sin shell. Protocolo binario con longitud máxima, cabecera JSON y payload RGB; stdout reservado al protocolo, stderr a logs sanitizados. Timeouts, handshake y terminación del proceso hijo.
- [x] T6 [otp] Coordinador supervisado con una inferencia en vuelo y un fotograma pendiente reemplazable por cámara; límite global de workers y memoria. No crear tareas sin límite ni bloquear callback Membrane esperando Python. Descartar resultados de generación anterior; expiración de cajas, reinicio con backoff y cierre por inactividad.

## Fase 3 — Integración Elixir y video
- [x] T7 [media] Implementar adaptador Elixir YOLO/Ortex y normalizar bbox cx/cy/w/h a xyxy. Aplicar filtro [0,2] antes de renderizar y publicar datos. Definir sesiones/modelos compartidos por worker de forma acotada, sin asumir que una sesión admite concurrencia ilimitada.
- [x] T8 [media] Implementar renderer y política temporal común: PTS intacto, resultados aplicados al frame correspondiente o retenidos con edad máxima explícita; medir desfase si se reutilizan cajas. Comparar modos :live y :live_low_latency; no presentar cajas atrasadas como exactas. Encoder H264 con keyframes/segmentación compatibles con HLS.
- [x] T9 [otp] Extender claves Registry, rutas y URLs HLS con motor validado y generación aislada. Separar salida original/anotada y garantizar parada de decoder/encoder/worker/modelo al quitar o expirar streams. Fallo del detector no causa un ciclo infinito: estado visible y botón para volver al original.

## Fase 4 — Interfaz
- [x] T10 [liveview] Añadir selector de motor, activación y estado por tarjeta con `.input`, `to_form`, IDs estables, Layouts.app y streams existentes. Reinsertar tarjeta al actualizar. Validar motor del lado servidor; mantener URLs RTSP privadas.
- [x] T11 [liveview] Integrar nueva generación en HlsPlayer, listeners y cleanup. Evitar suscripciones/players duplicados; probar cambio de calidad, reconexión, dos espectadores de la misma cámara y cambio de motor sin afectar tarjetas vecinas.

## Fase 5 — Validación y decisión
- [x] T12 [testing] Tests de contrato/filtro/letterbox/RGB-BGR y resultados vacíos, trabajador muerto, timeout, cola saturada, fin de video y generación obsoleta. Usar start_supervised!, monitores y sincronización determinista; sin Process.sleep. Inferencia real separada de fakes y de la suite habitual.
- [x] T13 [testing] Pruebas LiveView por IDs, tests JS de hook, rutas/archivos HLS por motor; smoke con clips y cámara real. Asegurar que ninguna clase ajena aparece dibujada ni publicada. Verificar recuperación y consumo acotado con varios clientes.
- [ ] T14 [benchmark] Crear runner reproducible para 1/4/8 streams y original/Python/Elixir; clips idénticos, mismo muestreo y configuración. Warm-up separado, tres repeticiones de al menos 60s; medir inferencia p50/p95, FPS inferidos/emitidos, descartes, edad de cajas, latencia punta a punta, RSS del árbol BEAM/Python/nativos, CPU y errores. Anotar manualmente frames para precisión/recall por clase; no llamar precisión a concordancia entre motores. Entregar CSV/JSON y MP4 anotados de ambos. Elegir por estabilidad, exactitud y costo total; documentar límites reales si 8 cámaras saturan.
- [ ] T15 [verification] Consultar mix help de cada task antes de usarlo; ejecutar compile --warnings-as-errors, format --check-formatted, pruebas focalizadas, JS, Python y assets.build; finalizar con mix precommit y git diff --check. Credo solo si ya se incorporó por decisión explícita: no existe hoy en mix.exs. Documentar instalación, configuración, comandos y resultado comparativo.

## Criterios de aceptación
Solo clases 0/2; cajas visibles en video HLS; ambos motores seleccionables y probados con el mismo material; video original disponible; reconexión y cola acotada verificadas; secretos fuera del cliente/logs. Dos MP4 y reporte con cifras reales. Objetivo exploratorio 5 inferencias/s a 640 para una cámara; no es garantía y deberá ajustarse con evidencia. No declarar equivalentes .pt/.onnx sin comparar resultados.

## Riesgos y autoevaluación
1. ¿La inferencia puede bloquear o agotar memoria? Mitigar con presupuesto global, cola reemplazable y pruebas de saturación; medir memoria fuera del heap BEAM.
2. ¿Las cajas corresponden al video? Quemarlas antes de HLS, conservar PTS y registrar edad; la reutilización de resultados sigue causando desfase y debe cuantificarse.
3. ¿La comparación decide motor o hardware/modelo? Mismos pesos/configuración/muestreo, CPU base y aceleradores reportados aparte; medir decode/render/encode además de inferencia.
Spikes no ejecutados: resolución de deps, toolchain nativo, export ONNX, H265 y disponibilidad efectiva de aceleración. No se requiere decidir el motor definitivo antes de obtener el reporte.

## Fuentes
Ver `research/evidencia.md`, notebook original, https://github.com/membraneframework/membrane_demo/tree/master/yolo y https://yolo.hexdocs.pm/readme.html.
