# Conteo continuo de cruces

Cada regla habilitada inicia un proceso canónico de analítica independiente de HLS.
Usa RTSP secundaria, decodifica H264/H265 a RGB de 640 px y comparte el detector
Python/Elixir existente. No guarda video ni requiere abrir `/cameras`.

## Preparación y calibración

1. Configura `CAMERA_RTSP_SOURCES_FILE` como indica [monitoreo](monitoring.md).
   Instala los modelos según [detección](detection.md).
2. Ejecuta `mix ecto.migrate` y `mix phx.server`.
3. Desde localhost abre `/cameras`, agrega una cámara y pulsa **Configurar conteo**.
   Dibuja la línea, arrastra sus extremos o muévela completa. Los campos numéricos
   permiten calibrar sin arrastrar. Los extremos se guardan normalizados de 0 a 1,
   excluyendo las bandas negras del video. Cierra la calibración para operar el video.
4. La línea va de verde a amarillo. Si es horizontal de izquierda a derecha,
   positivo significa hacia abajo. Selecciona dirección de entrada, motor y confianza
   (0.35–1). Habilita y guarda. Verifica entradas/salidas reales antes de usar los datos.
5. Consulta `/visitors`: filtros de cámara/días UTC/dirección, páginas de 24 eventos,
   totales del periodo y detalle con JPEG. El día final es inclusivo.

En IEx también puedes configurar una cámara del catálogo:

```elixir
Sentinel.VisitorCounting.configure_rule("division-1", %{
  x1: 0.1, y1: 0.5, x2: 0.9, y2: 0.5,
  engine: "python", entry_direction: "positive", confidence: 0.5, enabled: true
})
Sentinel.VisitorCounting.Manager.sync()
Sentinel.VisitorCounting.Manager.status("division-1")
Sentinel.VisitorCounting.Writer.stats("division-1")
Sentinel.VisitorCounting.totals(%{"camera_id" => "division-1"})
```

`min_hits` (2–30, defecto 3), `max_missed` (0–30, defecto 5) e `hysteresis`
(0–0.2, defecto 0.025, estrictamente positiva) se pueden ajustar mediante el contexto.
Una regla nueva está deshabilitada. Las revisiones provocan reinicio de su sesión.

## Configuración y capacidad

| Variable | Defecto | Uso |
| --- | --- | --- |
| `VISITOR_SNAPSHOT_ROOT` | `tmp/visitor-snapshots` absoluto | Directorio privado exclusivo de Sentinel |
| `VISITOR_MAX_CAMERAS` | 2 | Analíticas simultáneas, 1–8 |
| `VISITOR_QUEUE_CAPACITY` | 8 | Frames/eventos admitidos para escritura, 1–128 |
| `VISITOR_RETENTION_DAYS` | 7 | Retención finita, 1–365 días |

La raíz debe ser absoluta y canónica, sin symlinks en ningún componente, fuera de
`priv/static` y sin ser un ancestro de esa carpeta. En macOS usa `/private/tmp/...`
en lugar de `/tmp/...`. Se establecen permisos 0700 para la raíz y 0600 para JPEG.
No permitas que otros usuarios/procesos modifiquen esta raíz; las comprobaciones
de rutas no sustituyen los permisos del sistema de archivos.

El límite de ocho workers de detección es compartido con los espectadores HLS.
Un contador puede indicar **sin capacidad** aunque el límite de cámaras permita
arrancarlo. Empieza con una cámara y mide CPU, memoria, inferencias y pérdidas
antes de ampliar. No hay una cifra de FPS ni precisión validada para esta función.

Reserva disco con margen: cruces/día × tamaño medio JPEG × retención, más colas
y margen de mantenimiento. Supervisa espacio libre externamente; no hay cuota
de disco automática. Un disco lleno produce reintentos y pérdidas observables.

## Guardado, recuperación y pérdidas

El punto de apoyo inferior central debe atravesar el segmento finito entre
dos lados fuera de la banda de histéresis tras detecciones consecutivas.
Alejarse a dos veces la banda rearma el track. Cada cruce posterior tiene un ordinal.
La clave de deduplicación incluye cámara, revisión, sesión, track y ordinal.
El índice único de PostgreSQL es la protección final contra carreras.

Solo se procesa cada resultado fresco con su frame exacto. La inferencia mantiene
un frame en vuelo y uno pendiente reemplazable. El escritor admite slots ETS
finitos antes de enviar mensajes: anota/codifica JPEG, escribe temporal + rename,
inserta metadatos y publica PubSub después del commit. Una clave ya guardada devuelve
la misma fila sin crear otra imagen. Errores SQL conocidos compensan el archivo;
una conexión perdida durante COMMIT es ambigua y conserva el archivo para reconciliar.

La reconexión usa backoff de 1–30 s, sesión nueva y watchdog de progreso.
**Cargando**, **contando**, **sin conexión**, **sin capacidad** y **saturado** aparecen
en cada cámara local. La cola muestra ocupación global; fallas/pérdidas corresponden
a la cámara y al arranque actual del escritor. Los contadores y la cola son volátiles:
un cierre abrupto pierde pendientes, y un reinicio no garantiza continuidad.
La supervisión reinicia las cámaras si reinicia el escritor. Los totales de DB
son solo eventos persistidos: no los interpretes como completos tras pérdidas.

Telemetría: `[:sentinel, :visitor_counting, :write]` con `saved`, `failures` o
`dropped`, y `camera_id`; los eventos existentes `[:sentinel, :detection, :frame]`,
`:video_drop` e `:inference` exponen descarte y latencia. Exporta estas métricas
externamente si necesitas conservarlas entre reinicios.

## Retención y huérfanos

El proceso de retención revisa hasta 100 filas expiradas cada minuto. Primero
confirma el borrado de filas y luego elimina sus archivos. Un fallo de archivo
deja un huérfano reportable; nunca se borra una captura todavía referenciada
para tratar de compensar un commit ambiguo.

```sh
mix visitors.retention                 # simulación y reporte de JPEG no referenciados
mix visitors.retention --days 7        # simulación con otro periodo
mix visitors.retention --apply         # aplicar un lote de hasta 100
```

Repite lotes si hay atraso y comprueba `file_errors`. El reporte de huérfanos es
solo lectura y puede incluir archivos en vuelo antes del commit. No lo uses como
lista de borrado automática: detén analíticas/escritor, comprueba PostgreSQL y
reconcilia antes. Los temporales `.tmp` tras un cierre abrupto requieren inspección
manual. Respalda PostgreSQL y la raíz de capturas conjuntamente.

## Exposición y privacidad

Historial, detalles, JPEG y edición de reglas se restringen a **loopback** IPv4/IPv6.
HTTP verifica el peer y LiveView vuelve a comprobarlo al conectar; los eventos
de calibración exigen además una cámara seleccionada y acceso local asignado
por el servidor. Las rutas aceptan IDs de evento, nunca rutas de archivo.
Los JPEG se sirven con `Cache-Control: private, no-store` y no son estáticos.

No publiques estas rutas mediante un proxy local abierto: para Sentinel ese proxy
es localhost. Restringe `/visitors` y la aplicación completa en el proxy/VPN/firewall,
o agrega autenticación/autorización antes de exponerlas. No se confía en
`X-Forwarded-For` enviado por clientes. La cuadrícula HLS ya existente conserva
su política anterior; esto no agrega autenticación general al proyecto.

## Límites y validación pendiente

Es un tracker geométrico online acotado a 100 detecciones/tracks, no SORT completo,
reconocimiento facial ni reidentificación. Personas juntas, oclusiones, ángulos,
saltos de frames y desconexiones pueden intercambiar IDs, omitir o duplicar pasos.
Los IDs solo viven en la sesión de cámara. Cuenta cruces, **no visitantes únicos**.

Pruebas automatizadas cubren contexto, dedup, JPEG, geometría, jitter/reentrada,
capacidad, reconexión, independencia HLS, cola, retención, filtros y acceso.
`mix precommit` incluye también los hooks JS. Credo no se añadió por decisión
del usuario. El navegador integrado no está disponible en esta sesión: falta QA
visual de calibración. Falta un video de cruces anotado y representativo para
comparar ambos backends, FPS/latencia y precisión por cámara; los fixtures existentes
de autos y fotos no prueban esos criterios. No afirmar precisión general.
