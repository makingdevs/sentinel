# Evidencia — 2026-11-17

## Notebook
Leído como JSON sin ejecutar celdas ni outputs: `/Users/makingdevs/Downloads/Taller de Visión Computarizada con Python para Urbanismo/Sesion4Urbana/Sesion_4Urbana.ipynb`.
Celdas 6/9: yolov8n.pt. Celda 15: yolo11n.pt cargado una vez y OpenCV VideoCapture; sin filtro de clases. Celda 13: xyxy/conf. COCO: person=0, car=2. Celda 11 contradice su comentario (filtra 0,1,5,7); no copiar ese filtro. Tracking, líneas, zonas y pose son ejercicios adicionales, fuera del alcance inicial. No copiar imshow/waitKey a un servidor.

## Sentinel
`lib/sentinel/monitoring/pipeline.ex`: RTSP TCP → H264/H265 → SinkBin HLS; sin decoder, inferencia ni Python. Segmentos de 4s, ventana 24s (no implica latencia exacta de 24s).
`stream.ex`: proceso temporal por cámara/calidad, Registry/DynamicSupervisor, idle 60s, stall 30s; generación nueva al conectar, borra segmentos anteriores.
`monitoring.ex`: catálogo validado, URLs RTSP privadas, URLs HLS del mismo origen.
`camera_live.ex` y template: hasta 8 cámaras, streams LiveView, calidad secundaria/principal y generación de player.
`assets/js/hooks/hls_player.mjs`: Hls.js o HLS nativo, contenedor ignore, cleanup y reintentos.
`mix.exs`: no YOLO/Python/Credo. precommit = compile --warnings-as-errors, deps.unlock --unused, format, test. Tests usan PostgreSQL localhost. `mix help precommit` consultado.
Entorno inspeccionado: arm64, python3 y ffmpeg disponibles; cargo es shim (toolchain sin verificar), cmake no localizado. No se midió GPU, rendimiento ni memoria.

## Fuentes actuales
- Context7 `/membraneframework/membrane_core`: buffers/flow control/timestamps; una rama de análisis no debe bloquear la distribución.
- Context7 `/ultralytics/ultralytics`: predict/classes, results/boxes, export ONNX. Resolución de “yolo Elixir” no encontró la biblioteca correcta: se consultó HexDocs directamente, no el homónimo Python.
- https://yolo.hexdocs.pm/readme.html (v0.2.0): ONNX/Ortex, YOLO.load, YOLO.detect, modelos Ultralytics/YOLOX; Nx para pre/postproceso. eps CPU/CoreML según build. bbox cx,cy,w,h: requiere conversión a xyxy.
- https://github.com/membraneframework/membrane_demo/tree/master/yolo y `yolo/yolo.livemd` descargado a `/tmp/sentinel-yolo-demo.livemd`: decode → RGB → Detector → Drawer → I420 → WebRTC/MP4. Modelo del demo YOLOX-L: no sirve para comparar directamente contra yolo11n. No copiar Kino, cámara local, WebRTC ni configuración CUDA automática.
- https://membrane-yolo-plugin.hexdocs.pm/Membrane.YOLO.Detector.html (v0.1.2): raw RGB, metadatos; :offline todos, :live muestreo adaptativo con latencia, :live_low_latency cajas retrasadas.
- https://hexdocs.pm/membrane_yolo_plugin/Membrane.YOLO.Drawer.html (página servida v0.1.0): consume metadata detected_objects. Confirmar versión resuelta y código antes de integrar.

## Decisión
Un solo plan comparativo, dos adaptadores detrás de un contrato y renderer comunes. Python primero como referencia del notebook; Elixir después con el mismo modelo. Quemar cajas antes de HLS evita sumar un problema de sincronización entre PubSub y el video retrasado. No inferir ni cargar modelos dentro de LiveView. No introducir Ecto/Oban: no se pidió historial ni jobs batch.
Compatibilidad de plugins, decoders H265 y aceleración son spikes explícitos, no hechos comprobados. Ninguna implementación ni benchmark ejecutados.
