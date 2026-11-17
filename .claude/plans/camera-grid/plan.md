# LiveView de monitoreo de cámaras

Estado: ejecución autorizada; implementación local lista, validación operativa pendiente. Profundidad: estándar. Una entrega en tres fases, siete tareas.

## Objetivo y acuerdos
Seleccionar cámaras de División y La Virgen para verlas simultáneamente en una cuadrícula accesible desde Internet sin VPN. Sin autenticación durante esta etapa por decisión del usuario. HLS aceptado por tolerancia a varios segundos de retraso. Implementación autorizada por el usuario el 2026-11-16.

## Adaptación Membrane autorizada

El usuario aprobó sustituir la entrega por iframe con el ejemplo `rtsp_to_hls`.
La implementación recibe RTSP sobre TCP, genera HLS en disco y lo sirve desde
Sentinel. Un hook por tarjeta reproduce con hls.js/HLS nativo. La configuración
privada se carga desde `CAMERA_RTSP_SOURCES_FILE`; puede usar DVR directamente
o el RTSP existente de MediaMTX. Se confirmó una fuente HEVC 704×480 y video
real en Chrome/macOS. Guía vigente: `docs/monitoring.md`.

Las dos tareas infra originales sobre HTTPS HLS de MediaMTX quedan sustituidas
por configurar fuentes y HTTPS público de Sentinel; no son requisitos de la
nueva arquitectura. La aceptación pública y las pruebas de ocho cámaras siguen
pendientes. El diseño original se conserva abajo como historial.

- [x] Pipeline compartida por cámara/calidad, TCP, H.264/H.265 sin transcodificar.
- [x] Entrega HLS local con validación, publicación atómica y retención acotada.
- [x] Reproductor con hook, errores, reintento y liberación de recursos.
- [x] Pruebas automatizadas y reproducción local de una fuente real.
- [x] Verificación final y revisión local de la adaptación — 25 pruebas Elixir, 5 JS, assets/formato/compilación y auditoría rápida pasan.
- [ ] HTTPS público, prueba fuera de VPN, ambos sitios, Safari/móvil y carga de ocho cámaras.

## Diseño original (sustituido)
- Ruta `/cameras`, `SentinelWeb.CameraLive`, plantilla dentro de `<Layouts.app flash={@flash}>` con variante amplia del layout.
- Selector agrupado por sucursal para ocho cámaras, con agregar/quitar; no tratar sus dieciséis streams como dieciséis cámaras distintas.
- Inicio vacío; secundaria predeterminada y selector principal/secundaria por cámara. Estos valores son propuestas ajustables.
- Catálogo explícito en configuración Elixir con ID, sucursal, etiqueta y paths permitidos. `Sentinel.Monitoring` expone catálogo y construye URLs; no lee Downloads en ejecución ni incluye RTSP/credenciales.
- Base pública configurable mediante `MEDIAMTX_HLS_BASE_URL`, propuesta `https://monitor.agorabarrade.cafe:8888`.
- Iframe HLS por tarjeta, reproducción silenciada, inline y controles. Sin dependencia JS ni hook propio en el MVP; navegador descarga el video directamente desde MediaMTX.
- Streams con IDs estables para tarjetas, sin reiniciar otros reproductores al agregar/quitar. Cambiar calidad sustituye solamente el iframe afectado mediante identidad que incluya calidad. Validar este comportamiento en navegador.
- Selección mantenida durante sesión LiveView; recarga completa inicia vacía. Sin persistencia, API remota, Ecto, Oban ni grabaciones.
- El reproductor de MediaMTX muestra carga/errores; la aplicación no afirma que una cámara está en línea basándose en carga del iframe. Agregar acción de reintento que sustituye sólo ese reproductor.

## Mapa de interacción
```text
Usuario → /cameras → catálogo agrupado
  agregar cámara → validar ID → insertar tarjeta en stream
  quitar cámara → borrar tarjeta → navegador libera iframe/conexiones
  cambiar calidad/reintentar → sustituir iframe de esa tarjeta
Navegador → HTTPS MediaMTX:8888/<path> → playlist/segmentos HLS → DVR vía RTSP
Phoenix transmite selección/HTML por LiveView; no transporta video.
```

## Fase 1: reproducción pública
- [ ] [infra] Verificar versión instalada de MediaMTX, DNS público del dominio, acceso TCP 8888 desde fuera de VPN y códec/resolución/bitrate de un stream secundario por sucursal. Probar compatibilidad HLS en navegadores objetivo; si el DVR entrega un códec incompatible, documentar y ajustar salida H.264 cuando sea posible. Transcodificación requiere evaluar recursos antes de añadirla.
- [ ] [infra] Preparar configuración HTTPS nativa con `hlsEncryption: true`, `hlsServerCert` y `hlsServerKey`; obtener certificado confiable para el dominio con renovación automatizada y recarga/reinicio según versión. Elegir desafío ACME según acceso real a DNS/servidor (DNS-01 evita abrir puertos de validación HTTP). Guardar plantilla sin secretos y guía de aplicación/restauración; verificar reproducción en `https://monitor.agorabarrade.cafe:8888/<path>`. No asumir certificado existente ni ejecutar cambios remotos sin acceso autorizado. No hace falta habilitar HTTPS de WebRTC para este alcance.

## Fase 2: aplicación
- [x] [context] Crear catálogo configurable y `Sentinel.Monitoring` con IDs/paths explícitos de ambas sucursales; validar ID y calidad contra catálogo, no concatenar entrada arbitraria. Configurar base HTTPS en runtime; probar construcción de URL y rechazo de entradas desconocidas.
- [x] [liveview] Agregar ruta y CameraLive con formulario `to_form`/`<.input>`, selección sin duplicados, límite de ocho cámaras físicas, acciones quitar/limpiar, calidad individual y reintento. Stream de tarjetas con contador/selección separada, catálogo agrupado también renderizado con streams si corresponde a colección. IDs estables para controles y tarjetas; reinsertar tarjeta al modificar assigns que afecten su contenido.
- [x] [liveview] Crear cuadrícula responsive (una columna móvil, dos/tres según ancho), tarjetas 16:9, estado vacío y selector agrupado accesible. Ampliar layout sin afectar página existente; Tailwind/CSS propio, `<.icon>`, sin daisyUI nuevo ni scripts externos. Iframes con título accesible, fullscreen y autoplay permitido; mantener restantes reproductores al actualizar selección. Conservar errores dentro del reproductor y permitir reintentar una cámara.

## Fase 3: validación
- [ ] [test] Pruebas de contexto y LiveView por resultados: inicio vacío, agregar de ambas sucursales, duplicados, quitar/limpiar, cambio de calidad aislado, reintento, IDs/calidades inválidos. Usar `element/has_element?` e IDs, sin HTML crudo ni depender de AWS. Verificación manual real fuera de VPN con varias cámaras, Chrome/Safari y móvil, interrupción de stream, fullscreen y consola/red: sin mixed content, iframe ajeno sin recarga y conexiones liberadas al eliminar. No afirmar reproducción real a partir de tests de markup.
- [ ] [verify] Consultar `mix help` antes de tareas utilizadas; ejecutar `mix precommit` y build de assets. Credo sólo si se incorpora o ya existe al implementar; no añadirlo para este cambio. Registrar resultados y cualquier validación remota pendiente. Verificar carga con hasta ocho secundarias y medir consumo al cambiar a principal, sin prometer capacidad no medida.

## Criterios de aceptación
Es posible elegir cualquier subconjunto de ocho cámaras y reproducirlo simultáneamente desde Internet por HTTPS. Cada cambio afecta únicamente a la cámara indicada. No aparecen direcciones privadas de origen ni credenciales en HTML/configuración versionada. La interfaz funciona sin login durante desarrollo y no requiere acceso público a la API de MediaMTX.

## Riesgos y límites
El servidor público y códecs aún no se verificaron. DNS/certificado son prerrequisitos operativos. HTTPS cifra tráfico pero no restringe quién ve cámaras; autenticación aplazada explícitamente. El iframe permite avanzar con el reproductor oficial, pero la futura seguridad por tokens o estados integrados puede requerir un reproductor controlado mediante hook. Ocho videos pueden consumir ancho de banda y decodificación considerables; secundaria por defecto reduce demanda, no garantiza rendimiento.

## Evidencia
Evidencia inicial: `research/findings.md`. Esa investigación precede a la implementación; los resultados posteriores están en `progress.md` y `verification.md`.

## Avance de ejecución

Implementación local y pruebas automatizadas disponibles. Las tareas infra y la
validación real de la fase 3 siguen abiertas: falta acceso al servidor/DNS,
HTTPS operativo, códecs, Safari/móvil, identidad DOM/red y medición de carga.
Plantilla y procedimiento: `docs/mediamtx/hls-https.yml`, `docs/monitoring.md`.
El detalle de ejecución y comandos se conserva en `progress.md`.
