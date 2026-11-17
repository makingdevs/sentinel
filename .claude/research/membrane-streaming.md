# Ejemplos Membrane para Sentinel

Fecha: 2026-11-16. Alcance: revisión documental y de código; no ejecución de demos
ni modificación de la aplicación. Se inspeccionó la copia local en Downloads
(commit b14b20dba794fd294970cda9e1c20e220b47fddb) y se contrastaron pipelines,
controlador HLS y dependencias RTSP con archivos upstream mediante GitHub.
Documentación complementaria consultada mediante Context7: Membrane Core y hls.js.

## Resultado

Sí existen ejemplos aprovechables. `rtsp_to_hls` es el mejor punto de partida
para recibir nuestras cámaras/DVR; `rtmp_to_hls` aporta la integración Phoenix
que sirve playlists y segmentos y los reproduce en HTML. Para la aplicación
actual recomiendo primero aprovechar el reproductor HLS manteniendo MediaMTX;
un backend Membrane tiene sentido si queremos controlar también ingestión,
procesamiento o transcodificación desde Elixir.

## Comparación

| Ejemplo | Qué hace | Aplicación al proyecto |
|---|---|---|
| rtsp_to_hls | RTSP → HLS en archivos | Encaja con los DVR existentes; candidato para una prueba de una cámara |
| rtmp_to_hls | Recibe publicación RTMP → HLS servido por Phoenix | Referencia de servidor y reproductor; requiere publicador RTMP o puente |
| rtmp_to_adaptive_hls | RTMP → varias resoluciones/fps → HLS adaptativo | Útil si necesitamos adaptación automática; añade decodificación y codificación |
| camera_to_hls | Captura cámara local → HLS | Demostración útil, origen distinto de nuestras cámaras de red |
| webrtc_live_view | WebRTC y LiveViews dedicados | Alternativa si exigimos menor latencia; no es necesaria para HLS aceptado |

RTMP sería el protocolo de entrada al servidor, no una URL para poner en el
`src` de un video HTML. Los ejemplos RTMP seleccionados terminan entregando HLS
al navegador. HLS también puede generarse desde RTSP; no necesitamos incorporar
RTMP para conseguir reproducción web de los DVR.

## Evidencia de código

### RTSP → HLS

[Pipeline RTSP](https://github.com/membraneframework/membrane_demo/blob/master/rtsp_to_hls/lib/pipeline.ex)
usa `Membrane.RTSP.Source`, transporte UDP con rango de puertos y
`Membrane.HTTPAdaptiveStream.SinkBin` con FileStorage. Configura segmentos de
4 segundos y una ventana de playlist de 120 segundos. Esa ventana NO es una
medición de latencia: el retardo final depende también de keyframes, buffering,
red y reproductor. Selecciona una pista por tipo y asume H.264 para video y AAC
para audio; no contiene un transcodificador que arregle H.265 automáticamente.

El [script](https://github.com/membraneframework/membrane_demo/blob/master/rtsp_to_hls/rtsp_to_hls.exs)
espera `:track_playable` y luego inicia un servidor HTTP local. No copiar su
borrado de directorio ni su proceso bloqueado como ciclo de vida de producción.
Su [README](https://github.com/membraneframework/membrane_demo/tree/master/rtsp_to_hls)
y script de la copia local muestran diferentes puertos de origen: comprobar
configuración real antes de ejecutar. No se ha probado acceso desde Sentinel al
RTSP de las sucursales. El transporte UDP necesita alcance a los puertos RTP;
evaluar TCP intercalado con la versión elegida si la topología lo requiere.

### RTMP → HLS servido por Phoenix

[Pipeline RTMP](https://github.com/membraneframework/membrane_demo/blob/master/rtmp_to_hls/lib/rtmp_to_hls/pipeline.ex)
conecta SourceBin con SinkBin, H.264/AAC, segmentos de 4 segundos y directorio
compartido `output`. El [README](https://github.com/membraneframework/membrane_demo/tree/master/rtmp_to_hls)
explica una fuente OBS que publica al receptor local en 9006. No es un cliente
que automáticamente lea cualquier URL RTMP remota.

El [controlador](https://github.com/membraneframework/membrane_demo/blob/master/rtmp_to_hls/lib/rtmp_to_hls_web/controllers/hls_controller.ex)
sirve archivos con `send_file`; la
[plantilla](https://github.com/membraneframework/membrane_demo/blob/master/rtmp_to_hls/lib/rtmp_to_hls_web/templates/page/index.html.heex)
usa hls.js y alternativa HLS nativa. Son referencias arquitectónicas: no copiar
el controlador mínimo sin validar ID/nombre/ruta, MIME, política de caché y
manejo de segmentos que aún no existen o ya se eliminaron.

Para ocho cámaras se requieren rutas/directorios/manifiestos separados por
cámara/calidad. Los ejemplos usan un directorio fijo y no resuelven ese
multiplexado. Dimensionar retención y limpieza: ambos pipelines RTMP configuran
una ventana infinita; no asumir almacenamiento acotado para cámaras continuas.

### HLS adaptativo

[Pipeline adaptativo](https://github.com/membraneframework/membrane_demo/blob/master/rtmp_to_adaptive_hls/lib/rtmp_to_adaptive_hls/pipeline.ex)
crea variantes hasta 720p60, 720p30, 360p30, 180p30 y 180p2, filtradas según
entrada. Incluye decoder H.264, conversión de fps, escalado y encoder por rama.
El [README](https://github.com/membraneframework/membrane_demo/tree/master/rtmp_to_adaptive_hls)
usa Vidstack como reproductor. Inferencia: ocho cámaras con varias variantes
requieren medir recursos antes de adoptarlo. No equivale al selector manual
principal/secundaria que ya tenemos, ni combina automáticamente esas dos fuentes
del DVR en una playlist adaptativa.

## Integración recomendada

Primera opción, menor cambio:

```text
DVR → MediaMTX existente → HLS por HTTPS → video + hls.js en CameraLive
```

Reutilizar de los demos la reproducción `.m3u8`. Sustituir cada iframe por un
contenedor con ID estable, hook propio y `phx-update="ignore"`; importar hls.js
con versión fijada desde app.js, sin scripts inline ni CDN. Inicializar con
`Hls.isSupported()` y alternativa `video.canPlayType(...)`; liberar la instancia
con `destroy()` al quitar/reemplazar el reproductor. Conservar autoplay muted,
playsinline y controles. Exponer carga/errores desde eventos reales del player.
Cambiar calidad/reintentar debe reemplazar sólo ese player.

[hls.js oficial](https://github.com/video-dev/hls.js#embedding-hlsjs)
documenta ambas rutas y exige CORS para los recursos HLS cuando se piden desde
otro origen. Verificar playlist, segmentos y cualquier recurso referenciado.
El manejo del ciclo de vida aparece en
[Hls.destroy](https://github.com/video-dev/hls.js/blob/master/src/hls.ts).
Este cambio no corrige el TLS fallido de MediaMTX ni vuelve compatible un códec
que el navegador no decodifica.

Segunda opción, si queremos recibir video desde Elixir:

```text
DVR o RTSP de MediaMTX → pipeline Membrane compartido → HLS
→ servidor HTTPS de archivos → video + hls.js en CameraLive
```

Combinar ingestión `rtsp_to_hls` con entrega web `rtmp_to_hls`. Mantener fuentes
y credenciales sólo en configuración privada del backend; jamás en el HTML.
Una pipeline compartida por fuente/calidad, con supervisión, reconexión,
observabilidad y control de espectadores; evitar una pipeline por cada LiveView.
La [guía de integración Membrane](https://github.com/membraneframework/membrane_core/blob/master/guides/useful_concepts/running_membrane_in_elixir_application.md)
explica pipelines supervisadas. Un origen remoto siempre requiere conectividad
desde el servidor de procesamiento, aun si el navegador ya no usa VPN.

Servir HLS desde el origen HTTPS de Sentinel podría evitar que el navegador
acceda al HTTPS de MediaMTX, si el backend recibe RTSP por una ruta alcanzable.
Esto añade responsabilidad de transporte y distribución a nuestro despliegue;
no es un arreglo automático del problema de red actual.

## Versiones y siguiente experimento

El ejemplo RTMP local usa Phoenix ~>1.6 y LiveView ~>0.16; Sentinel usa Phoenix
~>1.8.16 y LiveView ~>1.2.0. Adaptar módulos/templates/hooks; no trasplantar
mix.exs ni el endpoint. El mix.exs RTSP contrastado upstream usa Membrane Core
~>1.0, plugin RTSP ~>0.7.0 y adaptive stream ~>0.19.0. Son restricciones del
ejemplo, no versiones recomendadas sin resolver compatibilidad y compilar.

Prueba propuesta: una secundaria H.264, inicialmente sólo video; comprobar
conectividad, manifiesto y segmentos, reproducir en Chrome/Safari, interrumpir y
reconectar, medir CPU/memoria/tráfico/latencia. Después ampliar a dos sucursales
y ocho cámaras. No se instalaron dependencias ni ejecutaron demos en esta revisión.
