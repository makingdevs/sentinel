# Evidence — visitor passage capture

## Local codebase findings

- `Sentinel.Detection.Filter` receives RGB frames, requests inference at 5 Hz, carries normalized `detected_objects` in frame metadata, and currently limits annotations to `person=0` and `car=2`. It has no track IDs, crossing state, snapshot capture, or event persistence.
- `Sentinel.Detection.Worker` already isolates backend calls from the Membrane filter. The production `Sentinel.Monitoring.Pipeline.annotate/3` decodes camera video to 640px RGB, then filters, draws, encodes H.264, and serves HLS. It is currently started only when HLS is requested; `Sentinel.Monitoring.Stream` reaps idle streams after 60 seconds and keys them by camera, quality, and engine. Thus analytics coupled to a viewer would stop counting when nobody watches, and independent viewer engine choices could create multiple detections for one camera.
- `Sentinel.Application` already supervises detector workers (max eight), `Sentinel.Repo`, `Sentinel.PubSub`, and camera stream processes. `Sentinel.Monitoring` owns the runtime camera catalog, but it has no camera Ecto schema or migrations. Use `camera_id` as a validated string matching the existing static catalog; do not introduce a camera table as part of the first increment.
- `SentinelWeb.CameraLive` uses Phoenix LiveView streams and the app currently has no business context, auth, visitor event UI, or snapshot route. `Image`/libvips is already a dependency and can encode frame snapshots without adding an image package.
- `Detection.Drawer` builds the overlay from current detections. A passage event should retain one selected full frame with the tracked person's box/label, rather than retaining video or one image per detection frame.
- `Sentinel.Repo` is configured for PostgreSQL; `priv/repo/migrations` contains no schema migrations yet. Tests use `Sentinel.DataCase` and PostgreSQL's SQL sandbox.

## Documentation researched

- Ecto's official constraints/upserts guide recommends a database unique index for race-safe deduplication; changeset uniqueness validation alone cannot enforce cross-process uniqueness. Source: https://hexdocs.pm/ecto/constraints-and-upserts.html
- LiveView supports a stream-backed collection with pagination/window limits; `Phoenix.LiveView.subscribe/3` can receive PubSub updates after the connected mount, and updates can use `stream_insert/4`. Source: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html
- Membrane Core filters can preserve timestamps/metadata in buffers and notify their parent. The project already attaches detection metadata to buffers. Source: https://hexdocs.pm/membrane_core/Membrane.Filter.html
- Elixir GenServer docs distinguish synchronous calls (backpressure) from asynchronous messages and warn that casts are not delivery acknowledgements; therefore media callbacks should not synchronously call a database writer, while the async handoff needs an explicit bounded queue and observable overflow policy. Source: https://hexdocs.pm/elixir/1.19.1/GenServer.html
- SORT proposes online tracking-by-detection using bounding-box association, a Kalman filter, and assignment; it is a useful lightweight baseline, but ID switches remain possible and must be evaluated in the site's camera views. Source: https://arxiv.org/abs/1602.00763
- Ultralytics documents persistent tracker state for consecutive frames from the same source. That feature is available to the Python backend but not inherently shared by the Elixir ONNX backend, supporting a shared post-detection BEAM tracker if backend results must have identical counting semantics. Source: https://docs.ultralytics.com/modes/track/

## Recommended scope and constraints

- Treat a “visitor” as one detected person's passage across one configured virtual line, not a known identity. Count again only after the track has exited/re-armed and later crosses again. Do not use face recognition, biometrics, cross-camera identity, or claim unique people.
- Configure one directed line with normalized endpoint coordinates per enabled camera. Track the bottom-center footpoint of person boxes through time, then count a signed side change across the line after a minimum track confirmation and hysteresis. Reset tracker state on source discontinuity; use a short, documented suppression window only to prevent reconnect replays, not to infer identity.
- Run one canonical, application-managed analytics process per enabled camera, independent of browser/HLS viewer selection and using the configured detector engine. The existing viewer pipeline remains responsible for preview only. Starting/stopping analytics from `/cameras` would miss traffic while no one watched and mix detector choices.
- Use a dedicated `Sentinel.VisitorCounting` context. Persist line settings and passage metadata in PostgreSQL. Give each crossing a deterministic idempotency key from rule ID/revision, pipeline session, tracker ID, and direction, guarded by a unique database index; the tracker latch handles per-track duplicate frames, the unique index protects retried/concurrent writes.
- Save one JPEG snapshot per confirmed crossing under a private, configured root, outside `priv/static`; write to a temporary file and atomically rename. Store only the generated relative key/path and compact bbox/confidence/direction metadata in PostgreSQL. A controller must resolve the event ID through the DB and never accept a filesystem path from a request. The current UI has no auth: production exposure of people images is a deployment gate until routes are authenticated/restricted.
- Separate frame encoding/file IO/DB work from media callbacks. Handoff one snapshot event to a supervised, bounded persistence queue, report backlog/overflow, and keep camera inference responsive. Define failure cleanup (remove orphan image on DB failure; retry only with same idempotency key), queue saturation behavior and event visibility in the operator UI.
- Add configurable retention and cleanup that deletes old rows and their JPEGs safely. Defaults require owner review; do not assume indefinite retention.

## Breadboard

`runtime camera catalog + persisted line rule -> VisitorCounting.Manager -> one canonical RTSP analytics pipeline/camera -> existing detector backend -> person-only tracker -> directed line crossing + re-arm -> bounded snapshot/event writer -> private JPEG + PostgreSQL unique event -> PubSub topic per camera -> VisitorCountingLive paginated list/counts -> event image controller`

The preview pipeline and its HLS controls stay independent. Calibration UI is reachable from `/cameras`; event history and date/direction filters live under `/visitors`.

## Research tracks

- [x] Existing detection pipeline and event metadata/frame ownership
- [x] Ecto schema, migration, repository and persistence conventions
- [x] Phoenix LiveView route/UI patterns and realtime refresh
- [x] Current Ecto/Phoenix docs for safe writes, pagination and LiveView updates
- [x] Image/frame storage lifecycle, bounded async processing and failure behavior
- [x] Tracking choice and limits for two detector backends

## Extended research — 2026-11-17

The user selected extensive research. Re-read detection Filter/Worker/LatestFrame/Drawer, Monitoring/Pipeline and catalog, Application, router, CameraLive, config, Mix aliases and sandbox helpers. Baseline `mix compile --warnings-as-errors` passes. There are no compound solution docs. No existing visitor modules or migrations. Mix requires escalation because Mix.PubSub opens a TCP socket.

Current Context7: Ecto official HexDocs (unique conflict handling), LiveView v1.2.0 (reset paginated streams, ignored hook DOM), Membrane Core (sink EOS and flow control). Revisited SORT original paper and Image / GenServer official docs. Installed source is authoritative for Image 0.54 API, rather than latest online 0.73 docs.

Implementation decisions:
- Consume fresh inference results with the exact submitted RGB frame; never count replayed overlay boxes attached to subsequent frames. Keep only one inflight and one replaceable pending frame.
- Include a crossing ordinal in dedupe identity; session/track/direction alone wrongly suppresses legitimate reentry in the same direction.
- Use a finite line segment with signed normalized distance, hysteresis and minimum consecutive detections. Bound tracks and detections; report losses. A geometric greedy association is a baseline, not SORT or an identity guarantee.
- Independent analytics pipeline ends at a sink, without encoder/HLS; session reset on reconnect. Existing preview worker limit is shared and can yield capacity status.
- Snapshot writes need per-event ownership and DB dedup before publication. Never delete the winning snapshot when a concurrent retry loses. Private root must reject traversal and symlinks, including parent directories.
- Queue admission must be bounded before sending full frames, not merely inside an unbounded GenServer mailbox. Use bounded admission tokens; retain references to RGB binaries only while admitted.
- Defaults: cameras disabled, conservative concurrency, finite retention. Restrict history, configuration and image access server-side, including connected LiveView, until an auth design exists.
- Credo is not a dependency; do not silently add it. Record unavailability as a verification limitation.
- Real camera/annotated clip and representative FPS measurements remain an empirical acceptance gate, not something synthetic tests can establish.

Sources: https://ecto.hexdocs.pm/constraints-and-upserts.html ; https://github.com/phoenixframework/phoenix_live_view/tree/v1.2.0 ; https://github.com/membraneframework/membrane_core ; https://arxiv.org/abs/1602.00763 ; https://hexdocs.pm/image/0.54.4/Image.html ; https://hexdocs.pm/elixir/1.19.1/GenServer.html
