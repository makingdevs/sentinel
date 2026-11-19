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

El catálogo y las conexiones se almacenan en PostgreSQL, en `cameras` y
`camera_sources`. `Sentinel.Monitoring` expone sólo los metadatos públicos y resuelve
las fuentes dentro del servidor. El arranque normal no lee archivos JSON ni necesita
`CAMERA_RTSP_SOURCES_FILE`.

Para bootstrap, prepara un JSON **local y privado** con los ocho IDs `division-1`
a `division-4` y `lavirgen-1` a `lavirgen-4`. Cada ID debe incluir **ambas** calidades,
`principal` y `secundaria`, con URLs de esquema `rtsp` y host. Esta entrada ilustra
el formato; repítelo para las ocho cámaras:

```json
{
  "division-1": {
    "secundaria": "rtsp://SERVIDOR:8554/RUTA_SECUNDARIA",
    "principal": "rtsp://SERVIDOR:8554/RUTA_PRINCIPAL"
  }
}
```

El archivo existente `tmp/camera_rtsp_sources.json` está ignorado por Git.
Restringe sus permisos (0600), no lo imprimas ni lo agregues al repositorio. Los
hosts y paths también identifican feeds privados aunque no incluyan credenciales.
Si la URL necesita usuario/contraseña, codifica sus caracteres reservados.

Orden para cada entorno, incluida una actualización de una instalación existente:

1. Instala dependencias y assets.
2. Aplica las migraciones a la base de datos del entorno.
3. Proporciona el JSON privado **sólo para ejecutar seeds** contra esa misma base.
4. Inicia o actualiza la aplicación sin la variable del JSON.

```sh
npm ci --prefix assets
mix deps.get
mix ecto.create
mix ecto.migrate
CAMERA_RTSP_SOURCES_FILE=/ruta/privada/cameras.json mix run priv/repo/seeds.exs
# La asignación anterior sólo aplica al comando de seeds.
PORT=4012 mix phx.server
```

`mix setup` también ejecuta seeds y por tanto requiere la variable durante ese
comando. En producción usa la configuración de PostgreSQL del entorno
(`MIX_ENV=prod`, `DATABASE_URL`, etc.) tanto al migrar como al sembrar. Para releases
sin Mix ejecuta la migración mediante el mecanismo de despliegue y llama a
`Sentinel.Monitoring.SeedImporter.import_file/1` en un nodo con Repo iniciado y
acceso temporal al archivo. No actives los workflows de cámaras antes de sembrar.

Seeds falla con un mensaje seguro si falta el archivo, hay JSON inválido o falta
una cámara/calidad válida; valida toda la entrada antes de escribir. Se puede
repetir: actualiza sucursal/etiqueta y URL/fecha de actualización mediante claves
explícitas, conserva IDs/fechas de creación y no borra filas ajenas. No agrega UI
de edición ni reescribe reglas o eventos históricos de conteo.

La aplicación arranca con la base vacía, pero sin catálogo no hay cámaras y las
fuentes ausentes fallan de forma segura. PostgreSQL debe estar disponible para
descubrir cámaras e iniciar streams. Las URLs permanecen en el servidor, con
logging SQL desactivado para lecturas/escrituras de fuentes y redacción RTSP en
logs. La base de datos y sus respaldos contienen endpoints sensibles: restringe
su acceso; no hay cifrado adicional de las URLs en la aplicación.

Después de sembrar, verifica sin la variable de runtime:

```sh
env -u CAMERA_RTSP_SOURCES_FILE bash scripts/detection/smoke.sh off
```

El smoke resuelve `division-1` / `secundaria` a través de Monitoring y PostgreSQL;
usa `DETECTION_CAMERA` y `DETECTION_QUALITY` para otra selección. Para todos los
motores omite `off`. Comprueba además HLS en `/cameras` y el contador habilitado
sin espectadores conforme a [operación de conteo](visitor-counting.md).

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
