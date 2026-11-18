# Visitor passage capture — research scratchpad

## Scope

Capture one event when a tracked person crosses a configured point/line in a camera view, persist the passage time and a frame, suppress duplicate detections of the same crossing, and show a paginated event list and counts.

## Assumptions to validate against the existing detection implementation

- A passage means crossing a camera-specific virtual line in a configured direction; ROI and direction are configurable per camera.
- Tracking IDs are short-lived and local to one stream. The feature counts passages, not unique people across visits or cameras; no face recognition or identity matching.
- Store an annotated frame as a local JPEG initially, with configurable retention and a storage abstraction for future object storage.
- Use a cooldown/re-arm rule in addition to tracker IDs so a person lingering near the line does not generate repeated events.
- Event persistence must not block frame inference or the live HLS pipeline. Bounded asynchronous handoff and supervised persistence are required.

## Selected research tracks

- [x] Existing detection pipeline and event metadata/frame ownership
- [x] Ecto schema, migration, repository and persistence conventions
- [x] Phoenix LiveView route/UI patterns and realtime refresh
- [x] Current Ecto/Phoenix docs for safe writes, pagination and LiveView updates
- [x] Image/frame storage lifecycle, bounded async processing and failure behavior
- [x] Tracking approach shared by both current inference backends

## Decisions / open issues

- Use a lightweight shared online tracker over person boxes so Python and Elixir yield identical crossing semantics. Evaluate with annotated clips; IDs are temporary and not identity.
- Retain annotated crossing JPEGs on private local storage with configurable cleanup; do not retain full video.
- Run analytics per enabled camera independent of HLS viewers to avoid missing passages when nobody watches.
- Count every configured directional passage after the track re-arms; do not claim globally unique visitors.

## Evidence

Research evidence is in `research/evidencia.md`. The plan is complete and awaits user review; implementation has not started.

### HANDOFF: visitor-passes — 2026-11-17
Status: 4/23 tasks implemented and verified; phase 1 gate awaits user decision on missing Credo. Next: resolve gate, then P2-T1 tracker.
Extensive research complete in research/evidencia.md. New context/schemas/migration/private snapshot persistence and four tests. Compile/format/focused tests pass. No commits. PostgreSQL test migration applied. No runtime analytics or visitor UI yet.
Decision needed: phx-work requires `mix credo --strict`, but project has no dependency/task. Ask whether to add Credo or accept existing gates; async question pending. Do not infer silence as approval.
Key decisions: exact inference frame only; crossing ordinal in dedupe; private root must be absolute/canonical and reject symlinks (macOS tests use /private/tmp); per-key advisory transaction lock before JPEG write; ambiguous DB connection loss preserves file for later orphan reconciliation. Shared Sandbox retry test is not proof of independent PostgreSQL connections racing. No representative annotated crossing clip verified yet. Existing fixtures/benchmark scripts may be reusable.

User resolved Credo gate: do not add dependency; continue using existing checks. Prior handoff gate is resolved.

### HANDOFF: visitor-passes — resumed after daemon recovery
Status: 19/23 tasks complete. Phases 1–4 complete; phase 5 blocked at P5-T4, phase 6 unchecked.
Next: P5-T4, supply/find a representative local video with a calibrated line and annotated entry/exit counts; run both backends on the same scene and measure latency/FPS, event/JPEG correspondence and viewer independence. User was asked for path/counts; no answer yet. Do not mark empirical acceptance complete using synthetic fixtures.
Checks: mix precommit PASS (65 Elixir + 8 JS); assets build PASS; format check and diff check PASS; retention dry-run PASS. Full suite already run once. Browser host unavailable so no visual QA. Dev + test migrations applied. No camera rule deliberately enabled in dev. No commits. Temporary smoke server PID 94482 was sent TERM; check its exit before restarting anything.
Decisions: no Credo per explicit user instruction. Loopback-only visitor history/JPEG/settings; proxies need upstream restriction/auth. Seven-day retention, 2 analytics cameras, 8 writer slots, shared detector max eight workers. Defaults disabled. Exact inference frames, session-local bounded greedy tracker, hysteresis rearm, ordinal dedupe, bounded ETS admission before messages. Metrics/queue volatile across restart. Ambiguous COMMIT loss leaves file for orphan reconciliation. README/docs record limitations and commands.
Recent robustness changes: manager startup clears orphan canonical children rather than adopt unknown revisions; status tolerates expected process-exit races; known SQL failures compensate snapshot; conflict returning existing event deletes only losing generated key. Final smoke and video quality gate are still required. To resume after supplying fixture, use --from P5-T4 to retry tagged blocker.

Live camera test (2026-11-18): tmp/camera_rtsp_sources.json, mode 0600; RTSP host reachable; division-1 secondary produced one FFmpeg frame (private transient /private/tmp/sentinel-live-check.jpg; grayscale empty shop view), master HLS HTTP 200 but media playlist/segment requests 503; Python worker was seen briefly but disappeared and count status stayed loading/error. Temporary rule x=.1..9, y=.5, positive, Python, conf .5 was disabled again (revision 3). No events or captures saved, no rule left enabled, server 4014 stopped. Missing issue is live inferencing/readiness and active passage; don't claim passage test complete. Check Detection.Worker/Python adapter logs/setup if resumed. The user's live-feed authorization permitted this one-camera test.
