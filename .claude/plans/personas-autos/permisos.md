# Comandos de ejecución validados

La implementación está autorizada por el usuario. No se requieren instalaciones globales para el entorno comprobado; Python3.12, Cargo y FFmpeg ya estaban disponibles. Las reglas técnicas del sandbox siguen vigentes y pueden solicitar aprobación si cambia el entorno.

## Scripts concretos (ya existen)

Ejecutar desde `/Users/makingdevs/sentinel`:

```bash
bash scripts/detection/setup.sh
bash scripts/detection/server.sh
bash scripts/detection/smoke.sh
bash scripts/detection/benchmark.sh
bash scripts/detection/benchmark.sh --profile-render
```

- Setup: venv local, `pip install --require-hashes`, modelo oficial con SHA256, export ONNX, `mix deps.get` y compilación. Descarga artefactos nativos a las cachés de Mix/XLA; contiene los flags de compatibilidad de Clang comprobados.
- Server: `mix phx.server`, puerto4013 por defecto, fuentes RTSP privadas desde archivo existente. No modifica las cámaras.
- Smoke: cámara configurada, tres motores,35s por motor; HLS temporal local. Espera la finalización de workers antes de cerrar el proceso.
- Benchmark: `MIX_ENV=prod`, fuente de video del taller local, 1/4/8 streams,3 repeticiones de60s más10s de calentamiento. No inicia el Repo ni el endpoint. Genera JSON/CSV/HLS locales. El entorno de DB/secret por defecto solo satisface runtime config de ese proceso de medición.
- Perfil: compara render original, SVG porframe y SVG con caché,100frames; no conecta cámaras.

Prefijos de scripts setup/smoke/benchmark/server son preferibles a autorizar intérpretes generales o `mix run` sin restricciones. Si falta algún permiso en otra sesión, aprobar el script concreto desde la solicitud del sistema. La aprobación en chat no reemplaza permisos del sistema.

## Verificación y herramientas locales

```bash
mix deps.get
mix deps.compile
mix compile --warnings-as-errors
mix format
mix format --check-formatted scripts/detection/*.exs
mix assets.build
mix precommit
.venv/bin/python -m pytest python/tests
node --test assets/js/hooks/hls_player.test.mjs
.venv/bin/python python/report.py
.venv/bin/python python/evaluate.py tmp/detection-python.json
.venv/bin/python python/evaluate.py tmp/detection-elixir.json
git diff --check
```

`mix test`/`precommit` usan PostgreSQL local y la base `sentinel_test`; no usan la base de producción. Los scripts de evaluación/reportes solo leen resultados locales. `curl` se utilizó para documentación y fixtures oficiales; no se subieron videos a servicios externos.

## Acciones adicionales realizadas dentro del alcance

- Compilación EXLA con `CXX='c++ -Wno-missing-template-arg-list-after-template-kw -Wno-invalid-specialization'` para Xcode actual; recogida en setup/benchmark.
- Consulta de reporte de crash local de BEAM al investigar cierre prematuro de un NIF; no se modificó el sistema. Se añadió espera explícita del supervisor antes de salir.
- Prueba visual en Chrome con localhost:4013; selector Python/Elixir y reproducción verificados.
- FFmpeg local para convertir fixtures y exportar MP4; escribe únicamente dentro de `tmp/`.

No forman parte de esta autorización: commit, push, deploy, cambios de credenciales o configuración de cámaras, instalaciones globales nuevas ni comandos destructivos sobre datos ajenos. No se necesita habilitar permisos generales sobre Downloads.
