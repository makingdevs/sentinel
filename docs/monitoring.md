# Cámaras: RTSP → Membrane → HLS

Sentinel adapta el ejemplo [rtsp_to_hls de Membrane](https://github.com/membraneframework/membrane_demo/tree/master/rtsp_to_hls).
El navegador reproduce HLS servido por Phoenix en `/hls/:camera/:quality/...`.
La cuadrícula `/cameras` conserva ocho cámaras, calidad individual, reintento,
quitar y limpiar. La selección sigue siendo temporal y sin login, según el
alcance aprobado. El video no viaja por el socket LiveView.

```text
DVR/cámara (RTSP sobre TCP)
  → Membrane.RTSP.Source
  → HTTPAdaptiveStream.SinkBin
  → playlists/segmentos locales
  → Phoenix /hls/...
  → video + hls.js (o HLS nativo)
```

También se puede usar el RTSP de MediaMTX como fuente intermedia. Ese fue el
origen usado en la prueba real local. No se requiere el servidor HLS ni HTTPS
de MediaMTX para esta arquitectura. El despliegue público de Sentinel sí debe
servir HTTPS y tener conectividad a las fuentes RTSP.

## Configurar las fuentes

El catálogo público está en `config/config.exs`. Las fuentes privadas se cargan
sólo en runtime desde `CAMERA_RTSP_SOURCES_FILE`, un archivo JSON fuera del código
versionado. No se lee Downloads en ejecución. Formato mínimo:

```json
{
  "division-1": {
    "secundaria": "rtsp://SERVIDOR:8554/RUTA_SECUNDARIA",
    "principal": "rtsp://SERVIDOR:8554/RUTA_PRINCIPAL"
  },
  "lavirgen-1": {
    "secundaria": "rtsp://OTRO_SERVIDOR:8554/RUTA_SECUNDARIA"
  }
}
```

Se admiten los IDs `division-1` a `division-4` y `lavirgen-1` a `lavirgen-4`;
las calidades son `secundaria` y `principal`. Configura sólo fuentes conocidas,
con permisos restringidos sobre el JSON (por ejemplo 0600). Si la URL necesita
usuario/contraseña, codifica sus caracteres reservados en el userinfo. La
aplicación no envía esas URLs al navegador y redacta orígenes RTSP y campos de
credenciales de los eventos de log.

```sh
npm ci --prefix assets
mix deps.get
CAMERA_RTSP_SOURCES_FILE=/ruta/privada/cameras.json mix phx.server
```

Para la prueba local se preparó `tmp/camera_rtsp_sources.json`, ignorado por Git,
con los paths RTSP ya conocidos de MediaMTX. El servidor de prueba usa puerto
4012. Para reproducir ese arranque:

```sh
CAMERA_RTSP_SOURCES_FILE="$PWD/tmp/camera_rtsp_sources.json" PORT=4012 mix phx.server
```

`CAMERA_HLS_DIRECTORY` permite escoger un directorio escribible. Su valor por
defecto es `tmp/hls` dentro de la aplicación. Debe ser privado, no un directorio
estático público: sólo el controlador validado entrega sus archivos. Cada
conversión usa un subdirectorio e identificador aleatorio propios. No es una
biblioteca de grabaciones ni almacenamiento persistente.

Si no hay fuente configurada, el endpoint responde 503 con Retry-After, sin
inventar conectividad. Un ID, calidad o nombre de archivo desconocido recibe
404. Los nombres no permiten rutas relativas ni extensiones ajenas a HLS.

## Ciclo de vida y entrega

- Una conversión compartida por cámara/calidad, iniciada al primer pedido HLS.
  Un Registry evita duplicados cuando llegan solicitudes simultáneas.
- Procesos bajo DynamicSupervisor; no se inicia una pipeline por LiveView.
- RTSP sobre TCP intercalado; sólo video, sin audio ni transcodificación.
- Detecta H.264 y H.265 desde las pistas anunciadas. Otro códec no se publica.
- Segmentos de al menos 4 segundos y ventana HLS de aproximadamente 24 segundos,
  condicionados por keyframes. La ventana no es una medición de latencia.
- Archivos publicados por renombrado atómico; playlists y segmentos se sirven
  sin caché para evitar cronologías antiguas. Los tipos MIME son explícitos.
- Una pipeline desconectada se vuelve a crear tras 3 segundos. Si no produce
  segmentos durante unos 30 segundos se detiene y reconecta. La reconexión usa
  nuevos nombres de pistas y descarta los archivos de la generación anterior.
- Sin solicitudes durante 60 segundos, se detiene y limpia sus archivos. Quitar
  una tarjeta cancela inmediatamente las descargas del reproductor; el origen
  compartido se libera después del período de inactividad, si nadie más lo ve.
- Cada hook tiene su propio reproductor y libera hls.js, listeners, fuente y
  temporizador al destruirse. Cambiar calidad/reintentar sustituye sólo su
  contenedor; los vecinos conservan identidad estable.

En producción con varias instancias, usa afinidad hacia la misma instancia para
las solicitudes de un stream o implementa un servicio multimedia compartido.
El Registry y el disco actual son locales a una instancia; el diseño no evita
conversiones duplicadas entre nodos ni comparte segmentos entre servidores.
Presupuesta ancho de banda: ahora Sentinel también entrega todos los videos.

## Códecs y comprobaciones reales

La secundaria de División probada anuncia HEVC/H.265, 704×480. Se recibió por
RTSP, se generó una playlist HLS con `hvc1`, se obtuvo HTTP 200 desde Sentinel y
se observó imagen real de la cámara en Chrome/macOS en `/cameras`.
Esto prueba una fuente en ese navegador, no ocho cámaras ni todos los clientes.

H.265 requiere soporte de navegador/sistema/hardware. El hook informa errores
incompatibles de códec y pide una salida H.264. Para compatibilidad más amplia,
configura H.264 en las cámaras/DVR o evalúa una etapa de transcodificación tras
medir CPU/GPU; no se promete que remultiplexar HEVC lo haga universal.

Pendiente en despliegue real: HTTPS público de Sentinel, acceso fuera de VPN,
Safari/iOS/Android, ambas sucursales y ocho fuentes a la vez, cambio de calidad,
fullscreen, desconexión/reconexión real, inspección DOM/Network y mediciones de
latencia, CPU, memoria y tráfico. El RTSP es una conexión del servidor, por lo
que ese servidor necesita ruta de red hacia cada origen.

## Dependencias

Membrane Core 1.3.6, RTSP plugin 0.7.2 y adaptive stream plugin 0.21.3 quedaron
resueltos en mix.lock; hls.js 1.6.19 se fija en assets/package-lock.json.
Req usa 0.6.3 porque ex_hls no admite el 0.7.5 anterior. Se conservan Ecto 3.14.3
y Decimal 3.2.0. Ratio 4.0.1 declara una restricción opcional de Decimal anterior
a la versión 3: se usa un override explícito de Decimal y una prueba de
interoperabilidad. Esta excepción debe revisarse al actualizar Ratio/Membrane.
Los paquetes upstream emiten avisos de deprecación/tipado bajo Elixir 1.19;
no se modificaron ni se silenciaron sus fuentes.

La plantilla `docs/mediamtx/hls-https.yml` queda como referencia histórica de la
arquitectura anterior; no es requisito para esta entrega con HLS local.
