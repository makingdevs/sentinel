# Detección de personas y autos

Profundidad: deep. Plan autorizado para implementación de ambos motores. Código funcional implementado; T14 matrizprod final en curso, T15 cierre documental pendiente. Ver progress.md y checkboxes de plan.md.

Investigación completada:
- [x] Notebook: modelo, clases y procesamiento
- [x] Sentinel: captura, transporte y reproducción
- [x] Documentación: Membrane, YOLO Elixir y Python
- [x] Arquitectura, sincronización, benchmark y permisos

Decisiones vigentes: dos motores, YOLO11n común, HLS y renderer comunes, cajas en píxeles antes de HLS. Sin tracking/conteo direccional. CPU como referencia; MPS/CoreML no medidos. Modelo nano no detecta los9autos de la imagen cenital anotada; no ocultar esa limitación ni llamar exactitud a concordancia entre motores.

Lecciones / dead ends:
- No copiar YOLOX-L del Livebook para comparar con nano PT. Extraer solo parsers/decoder/RGB y arquitectura de anotado; sin Kino/WebRTC/audio.
- Elixir yolo0.2 aplica reverse RGB cuando usa ImageScaler; se implementó preprocess RGB propio. Los índices de clase que retorna NMS son floats: redondear antes del filtro entero0/2.
- Nx.BinaryBackend costaba ~2s de pre/postproceso; EXLA+defn reduce esa demora. EXLA0.9.2 en Xcode actual necesita los dos flags CXX de setup.sh. No editar deps/vendor.
- Drawer original recalcula texto por cada frame. Nuevo SVG cacheado se materializa con Vix.copy_memory; no conservar pixeles de video en caché.
- Fixture Realtimer es push, TCP real es pull. LatestFrame con1pendiente y demandas1 protege ambos; inferencia pending1 por sí sola no acota colas del renderer.
- Cobertura=boxed_frames/input_frames, no dividir por frames después de encoder.
- Matriz inicial dev está en tmp/detection-benchmark-before-cache y research/before-cache.md. Resultado definitivo será tmp/detection-benchmark, ejecutado enprod. No mezclar cifras entre versiones.
- Ortex puede fallar al cerrar VM si queda dirty NIF trabajando. Runners ahora esperan Supervisor.stop de detectores y Worker.shutdown130s antes de salir; verificar que matrizfinal no registre cierres anormales.
- LogFilter debe usar Map.to_list en structs; Map.new(struct) fallaba y desactivaba filtro de redacción.

Estado verificado:39ExUnit,8Python,6JS, H264/H265, browserChrome Python/Elixir activos. Servidor4013 detenido durante benchmarks para evitar carga extra; volver a arrancar al terminar. Perfil aislado prod en tmp/detection-render-profile.json. Matriz final sesión7808, archivos incrementales tmp/detection-benchmark. Al acabar: generar reporte/MP4, verificar visualmente outputs y servir localhost4013/cameras. No commit/push/deploy solicitados.
