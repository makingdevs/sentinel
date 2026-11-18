# Capturar y contar pasos de personas

## Objetivo

Por cada cámara habilitada, detectar el cruce de personas por una línea virtual dibujada sobre la imagen, guardar una sola captura del cruce, y consultar eventos y conteos por cámara, periodo y dirección. El conteo representa **entradas/pasos**, no identidades únicas.

## Decisiones de producto y diseño

- **Conteo continuo:** la analítica se ejecuta para cada cámara habilitada aunque nadie tenga abierta `/cameras`. El motor se configura por cámara y permanece independiente de los motores de previsualización que elijan los espectadores.
- **Punto:** una línea dirigida y ajustable en cada cámara, almacenada en coordenadas normalizadas de 0 a 1 para que sobreviva a cambios de resolución. La calibración ocurre sobre el video de `/cameras`.
- **Cruce válido:** usar el punto inferior central de la caja de la persona. Exigir varias detecciones consecutivas, cruzar una banda de histéresis y entrar en la dirección configurada. El track se vuelve a armar después de alejarse del área; cada cruce válido posterior puede crear otro evento. La dirección que cuenta como entrada es configurable.
- **Identidad:** tracker geométrico online compartido después de ambos detectores, así Python y Elixir reciben la misma lógica de conteo. Los IDs viven solo dentro de una sesión de cámara. No se hace reconocimiento facial, reidentificación entre cámaras, ni conteo de visitantes únicos. Reinicios, oclusiones y personas muy juntas pueden producir misses o intercambios de ID.
- **Persistencia:** nueva frontera `Sentinel.VisitorCounting`; PostgreSQL guarda regla y metadatos del evento. Un JPEG anotado por cruce va a un directorio privado fuera de `priv/static`. Nunca se conserva video continuo.
- **Duplicados:** la máquina de estados del track evita emitir repetidamente mientras la persona permanece en la línea. Un `dedupe_key` único en PostgreSQL hace idempotente el guardado ante reintentos/concurrencia; se incluye sesión de cámara y versión de regla para que un ID temporal no colisione con otro.
- **Capacidad:** hay un proceso de analítica independiente por cámara y un máximo configurable. La escritura de JPEG y base de datos sucede fuera del callback de medios, mediante handoff supervisado, acotado y observable. Si se llena, el sistema muestra estado de saturación; no acumula frames en memoria sin límite.
- **Privacidad:** se conserva solo la imagen del cruce y metadatos mínimos. La retención es configurable y los JPEG no se sirven desde estáticos. La app no tiene autenticación ahora; antes de exponer la galería fuera de una red local, se debe restringir el servicio o agregar autorización para historial e imágenes.

## Mapa del sistema

```text
configuración de cámara + regla/línea persistida
  → VisitorCounting.Manager (un proceso canónico por cámara habilitada)
  → RTSP → decoder → RGB → detector configurado (Python o Elixir)
  → filtro person-only → tracker compartido → línea dirigida + histéresis
  → evento de cruce + frame RGB anotado
  → cola de escritura acotada → JPEG privado + PostgreSQL (dedupe_key único)
  → PubSub por cámara → VisitorCountingLive (lista paginada, capturas y totales)
```

El reproductor HLS continúa siendo una ruta independiente. Ver o cambiar el reproductor no inicia, detiene ni duplica el contador. El primer alcance contará `person=0`; los autos seguirán apareciendo en el video, pero no crearán eventos de visita.

## Fases

### 1. Persistencia y límite del contexto

- [ ] [ecto] Crear `Sentinel.VisitorCounting` con operaciones para buscar/configurar reglas, crear eventos de forma idempotente, filtrar por cámara/fechas/dirección, paginar y obtener totales.
- [ ] [ecto] Crear migraciones para `visitor_counting_rules` y `passage_events`: `camera_id` validado contra el catálogo estático existente; endpoints de línea normalizados; motor, dirección, umbrales, enabled/revision; `crossed_at`, `direction`, `tracking_session_id`, `track_id`, confianza, bbox y `snapshot_key`.
- [ ] [ecto] Añadir índices para `unique(camera_id)` de regla, `unique(dedupe_key)` de evento y consultas `(camera_id, crossed_at desc)`; documentar que la unicidad de base de datos es la protección final ante carreras.
- [ ] [ecto] Implementar almacenamiento privado de JPEG con clave generada por el servidor, validación de raíz, escritura temporal + rename atómico y compensación de archivo huérfano si la inserción DB falla. Guardar ruta relativa en DB; no almacenar el binario completo en PostgreSQL.

### 2. Detección de cruces sin duplicados

- [ ] [membrane] Añadir un tracker incremental por cámara que consuma solo cajas de personas de ambos motores, asigne IDs temporales por IoU/centro/movimiento y expire tracks perdidos. Mantener coste de CPU/memoria acotado y separar la implementación de los adapters YOLO.
- [ ] [membrane] Implementar regla de cruce dirigida sobre el punto de apoyo de la persona: lado anterior, banda de histéresis, confirmación mínima, dirección de entrada y rearmado después de salir. Emitir como máximo un evento por cruce confirmado; ignorar autos y detecciones que no alcanzan el umbral configurado.
- [ ] [membrane] Adjuntar al evento una sola copia referenciada del frame y metadatos mínimos; dibujar la caja/etiqueta de la persona en la captura. No codificar JPEG ni escribir archivos ni esperar a `Repo` dentro del callback de medios.
- [ ] [testing] Añadir pruebas de asociación de tracks, dos personas simultáneas, ausencia temporal/oclusión, cruce en ambas direcciones, jitter sobre la línea, rearmado/reentrada, detección duplicada por varios frames, reinicio de sesión y reglas inválidas.

### 3. Analítica permanente y resiliente

- [ ] [otp] Crear `VisitorCounting.Manager` y supervisor con un proceso canónico por cámara habilitada, clave única por cámara y límite de concurrencia. Arrancarlo después de `Repo`; sincronizar sus procesos al iniciar, cambiar regla, habilitar/deshabilitar una cámara y terminar limpiamente.
- [ ] [membrane] Crear el pipeline de analítica por cámara: abrir RTSP, decodificar H264/H265, convertir al tamaño de inferencia, usar el motor guardado en la regla, rastrear cruces y observar EOS/desconexión. Este pipeline no crea HLS ni depende del espectador.
- [ ] [otp] Gestionar reconexión con backoff, reset de trackers por nueva sesión, estados loading/active/error/capacity/saturated y métricas de cruces/frames perdidos/cola. No permitir que una segunda vista o motor cree otro contador para la misma cámara.
- [ ] [testing] Cubrir inicio/parada por cambios de reglas, límite de cámaras, recuperación de RTSP, cierre de procesos y no duplicación al abrir/cambiar espectadores HLS.

### 4. Guardado, historial y ciclo de vida

- [ ] [ecto] Añadir escritor supervisado de eventos: consumir de una cola limitada, persistir JPEG y fila con la misma clave idempotente, limpiar JPEG ante error de DB, y registrar/reintentar fallas con límites explícitos. Publicar evento solo después de persistirlo; observar saturación y contabilizar cruces que no pudieron guardarse.
- [ ] [ecto] Implementar retención configurable con borrado ordenado de filas/archivos, modo de simulación para operación manual y reporte de archivos huérfanos; no adoptar retención indefinida por defecto.
- [ ] [liveview] Añadir `VisitorCountingLive` en `/visitors`: filtro de cámara, rango de fechas y dirección; totales del periodo; stream paginado de capturas recientes con hora, confianza y enlace a evento. Recibir avisos PubSub y reconsultar/insertar el evento persistido, sin usar el stream para contar ni filtrar en memoria.
- [ ] [liveview] Servir capturas desde una acción que resuelve `event_id` por DB y verifica que la clave calculada permanezca dentro del directorio privado. Añadir control de acceso/restricción antes de exponer este endpoint fuera de la red local.

### 5. Calibración y operación

- [ ] [liveview] En `/cameras`, añadir acceso a configuración por cámara y un hook JS de calibración para dibujar/mover la línea sobre el video; convertir coordenadas del elemento a porcentajes normalizados y enviar endpoints/dirección con un formulario LiveView validado.
- [ ] [liveview] Mostrar si el contador está deshabilitado, cargando, contando o saturado; permitir seleccionar motor, dirección, umbral y habilitar/deshabilitar; explicar que el historial registra cruces y no personas únicas.
- [ ] Documentar variables de almacenamiento privado, límites de procesos, espacio de disco, retención, recuperación y exposición de imágenes. Añadir comandos para `mix ecto.migrate`, habilitar cámara y revisar conteo.
- [ ] [testing] Añadir fixture de video con línea calibrada y cruces conocidos. Verificar ambos backends con la misma escena, que cada evento tenga una sola imagen legible, que el conteo no dependa de la vista HLS y que la latencia/FPS siga dentro de límites.

### 6. Verificación final

- [ ] Ejecutar `mix compile --warnings-as-errors`, `mix format --check-formatted`, pruebas de contexto/Ecto, tracker/Media, LiveView y `mix precommit`; resolver fallos.
- [ ] Hacer smoke de una cámara configurada durante entrada/salida y desconexión; revisar manualmente las imágenes guardadas, la página `/visitors`, totales por periodo, duplicados y límite de retención.
- [ ] Actualizar `README.md` y documentación de operación con las limitaciones de tracking y la diferencia entre cruces y visitantes únicos. No afirmar precisión general sin anotaciones representativas por cámara.

## Criterios de aceptación

1. Con una cámara habilitada y ningún reproductor abierto, los cruces configurados siguen guardándose.
2. Una persona visible durante muchos frames cerca de la línea crea un solo evento de entrada; tras abandonar y volver a cruzar crea el siguiente evento.
3. El evento muestra hora, cámara, dirección, confianza y una imagen anotada servida desde el directorio privado.
4. Repetir una escritura con el mismo `dedupe_key` no crea una segunda fila ni una segunda captura huérfana.
5. La página de historial pagina eventos y publica totales calculados desde PostgreSQL por el filtro elegido.
6. Cambiar el motor del reproductor no altera ni duplica el contador canónico.
7. Un detector lento, cola llena o disco/DB en error no genera backlog de frames ilimitado ni bloquea HLS; el estado y cruces no guardados quedan visibles para el operador.

## Riesgos y decisiones pendientes

- **CPU continua:** el conteo independiente mantiene decodificación e inferencia por cámara habilitada. La matriz anterior de 1/4/8 streams debe informar el límite; habilitar todas las cámaras podría saturar la máquina. El administrador debe definir el límite permitido por hardware.
- **Calidad del tracking:** oclusiones, personas juntas, ángulo alto y detector que omite cajas pueden causar IDs intercambiados o cruces perdidos. SORT sustenta el enfoque de asociación online de cajas, pero cada cámara necesita ajuste y un clip anotado; no se puede garantizar identidad a través de desconexiones.
- **Dirección y significado:** la orientación de la línea define qué lado significa “entrada”. Se debe calibrar cada cámara y confirmar el conteo esperado antes de usar datos operativos.
- **Disco y privacidad:** JPEG por cruce requiere cuota y retención. El endpoint de imágenes no debe quedar expuesto públicamente sin autenticación; el proyecto actualmente no tiene auth.
- **Pérdida bajo sobrecarga:** la cola es limitada para proteger video. La política de saturación debe alertar y registrar el número de eventos/capturas que no se guardaron; nunca reportar un total como completo después de pérdidas.

## Verificación planeada

- ExUnit: `mix test test/sentinel/visitor_counting`
- LiveView: `mix test test/sentinel_web/live/visitor_counting_live_test.exs`
- Python/JS solo si el worker o los hooks existentes cambian; sus suites se deben sumar al precommit.
- Smoke: `mix ecto.migrate`, arranque de Sentinel y una cámara RTSP configurada; comprobar página `/visitors`, imágenes y reinicio del proceso.
- Revisión estática y final: `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix precommit`.
