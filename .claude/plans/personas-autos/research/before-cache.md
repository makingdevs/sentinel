# Diagnóstico inicial antes de cache/cola limitada (MIX_ENV=dev)

Esta matriz es exploratoria; la tabla definitiva se medirá en prod. La cobertura usa input_frames cuando existe; para las filas antiguas se estima con25FPS de entrada.

Equipo: Apple M1 Pro, macOS arm64; CPU, YOLO11n, entrada H264 a 640px/25FPS. Cada caso usa 10s de calentamiento y 60s de medición. Valores agregados: mediana de las repeticiones; RSS es el máximo observado. Python limita PyTorch a dos threads; Ortex usa su configuración automática. No son mediciones con igual presupuesto de threads.

| Motor | Streams | Repeticiones | Video FPS/stream | Inferencias/s/stream | Inferencia p95 ms | Edad cajas p95 ms | Frames con cajas % | RSS pico MB | CPU % | HLS listos |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| off | 1 | 3 | 25.0 | 0.0 | — | — | 0.0 | 195.3 | 5.1 | 1/1 |
| python | 1 | 3 | 25.0 | 4.75 | 50.6 | 244 | 100.0 | 642.5 | 102.9 | 1/1 |
| elixir | 1 | 3 | 25.0 | 4.65 | 72.8 | 278 | 100.0 | 416.5 | 160.1 | 1/1 |
| off | 4 | 3 | 25.0 | 0.0 | — | — | 0.0 | 247.4 | 14.7 | 4/4 |
| python | 4 | 3 | 17.8 | 4.82 | 83.2 | 278 | 100.0 | 2840.1 | 574.1 | 4/4 |
| elixir | 4 | 3 | 16.1 | 4.64 | 118.6 | 295 | 100.0 | 2350.0 | 703.3 | 4/4 |
| off | 8 | 3 | 25.0 | 0.0 | — | — | 0.0 | 350.8 | 29.5 | 8/8 |
| python | 8 | 3 | 8.9 | 4.44 | 267.4 | 421 | 97.7 | 3879.7 | 669.3 | 8/8 |
| elixir | 8 | 3 | 4.1 | 2.56 | 656.5 | 487 | 30.4 | 4429.2 | 762.8 | 8/8 |

La inferencia y el video tienen ritmos diferentes. Se conservan como máximo 500ms de cajas, por lo que bajo saturación puede haber video sin anotaciones. `pending_replacements` cuantifica fotogramas pendientes reemplazados; no equivale a frames perdidos del video.

RSS suma el árbol de procesos e incluye memoria nativa. CPU puede superar100%. Los ficheros JSON/CSV individuales quedan en `tmp/detection-benchmark/`; no se deben inferir garantías de producción ni precisión general a partir de estos clips.

La latencia registrada termina en la salida del encoder: excluye segmentación, HTTP y navegador. No se midió latencia completa de captura a pantalla. La comprobación de exactitud de dos imágenes está separada en `tmp/detection-accuracy.json`; es una muestra de plausibilidad con anotación manual, no un conjunto representativo.

Casos completados: 27/27. Errores de pipelines reportados: 0.
