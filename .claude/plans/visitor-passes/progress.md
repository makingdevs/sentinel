# Visitor passes progress

## 2026-11-17 — Research complete

Extensive research selected; findings in research/evidencia.md. Baseline compile PASS.

Started: P1-T1 — context and validated schemas.

Completed P1-T1: context + Rule/PassageEvent schemas; compile and format check PASS.
Started: P1-T2 — tables and DB checks.

Completed P1-T2: generated migration with normalized geometry and settings checks; compile/format PASS.
Started: P1-T3 — unique and history indexes.

Completed P1-T3: unique rules/dedupe and time indexes; compile/format PASS.
Started: P1-T4 — private snapshots and atomic persistence.

Completed P1-T4: private snapshot namespace, exclusive temp write and atomic rename, restrictive permissions, traversal/symlink/public-root rejection, transaction-scoped dedupe advisory lock, SQL failure compensation. Ambiguous DB connection loss intentionally leaves a possible orphan for reconciliation rather than delete a committed image.
Verification: compile warnings-as-errors PASS; format check PASS; context tests 4/4 PASS. Test alias applied migration successfully to sentinel_test. Tests cover rule validation/revision, readable JPEG, retry dedup, concurrent callers (shared SQL sandbox serializes underlying connection), filters/totals/pagination, failed insert compensation and unsafe roots/keys.
Phase 1 gate: BLOCKED awaiting user decision. `mix help credo` confirms task absent; no Credo dependency in mix.exs. phx-work requires strict Credo per phase; question submitted: add dependency or use existing gates with documented exception. No code retry can resolve missing tooling without this choice. No later phase started. Full suite/precommit still pending at final gate. No commits.

User decision: do not add Credo. Continue with existing compile, format, focused tests and precommit gates; Credo exception accepted. Phase 1 COMPLETED.
Started: P2-T1 — bounded geometric tracker.

Completed P2-T1: bounded person-only geometric/motion tracker; compile/format PASS.
Started: P2-T2 — finite directed line crossing state machine.

Completed P2-T2: directed finite segment FSM, footpoint/hysteresis/confirmation/rearm; compile/format PASS.
Started: P2-T3 — frame-referenced crossing events and deferred JPEG encoder.

Completed P2-T3: frame-referenced event with ordinal dedupe and deferred annotation/JPEG; compile/format PASS.
Started: P2-T4 — tracker and crossing behavior tests.

Completed P2-T4 / Phase 2: 11 focused tests PASS, including two people, jitter/reentry, occlusion expiry, session/direction, finite segment, bounds and readable annotated JPEG. Compile/format PASS. Credo omitted per user decision.
Started P3-T1: canonical camera supervision/manager.

Completed P3-T1: Registry, supervisor, manager/reconciliation and canonical camera identity; compile/format PASS.
Started P3-T2: viewer-independent RTSP analytics graph and fresh-result integration.

Completed P3-T2: separate RTSP H264/H265 decode/RGB/latest/detect/discard graph; fresh result retains exact frame and resets tracking on stream/detector changes. Compile/format PASS after fixing a comma typo. Writer admission connects in P4-T1.
Started P3-T3: reconnect/status/metrics.

Completed P3-T3: reconnect exponential backoff capped at 30s, progress watchdog, fresh tracking sessions and camera statuses; compile/format PASS. Writer queue saturation/metrics finish in P4-T1.
Started P3-T4: camera lifecycle/capacity/reconnect and HLS isolation tests.

Completed P3-T4 / Phase 3: compile/format PASS; 21 focused tests PASS (context/tracking/manager + existing detection and HLS streams). Starts/stops, capacity, new reconnect session, no viewer-driven duplicate, teardown verified with monitors.
Started P4-T1: bounded supervised writer, retries and publication.

Completed P4-T1: fixed ETS admission slots before messaging, worker-only JPEG/DB IO, 3 attempts, loss/failure/save telemetry, publish only inserted rows. Saturation and real JPEG/DB retry tests 2/2 PASS; compile/format PASS. Queue/metrics are volatile across app restarts.
Started P4-T2: finite retention and manual dry-run/orphan report.

Completed P4-T2: default 7-day retention, batches of 100/minute, row-first/file-second deletion with orphan report, manual dry-run task; context tests 5/5 PASS; compile/format PASS.
Started P4-T3: restricted paginated/filterable visitor history.

Completed P4-T3: loopback-protected history/detail routes, UTC validated filters, DB totals, 24-row stream pages, PubSub requery; 3 LiveView tests PASS; compile/format PASS.
Started P4-T4: DB-resolved private snapshot endpoint and negative access tests.

Completed P4-T4 / Phase 4: snapshot endpoint resolves DB event, safe private path, regular file, no-store; local restriction checked HTTP and WS mount. 23 affected tests PASS; compile/format PASS. Dev migration applied. Browser host unavailable; LiveView behavioral tests and local HTTP fallback used, visual QA remains unverified. Server on 4023 for smoke.
Started P5-T1: video line calibration hook and validated camera form.

Completed P5-T1: video-aware normalized SVG calibration hook (draw/endpoints/whole-line drag), numerical fallback, server-validated rule form, selected-camera/loopback checks; compile/format PASS. Browser unavailable, interaction tests follow in phase gate.
Started P5-T2: analytics controls/status/loss visibility.

Completed P5-T2: independent engine/direction/confidence/enable controls; loading/active/error/capacity/queue saturation, lifetime failures/loss warning; compile/format PASS, JS normalization tests 2/2 PASS, calibration/preview tests PASS after correcting peer_data test fixture.
Started P5-T3: runtime/operations docs and precommit hook tests.

Completed P5-T3: docs/visitor-counting.md, README, validated runtime env vars, explicit JS hook tests in precommit. Compile/format PASS. Assets build PASS. Manual `mix visitors.retention` dry-run PASS, no expired rows or orphans. Added exact inference-frame admission test and manager restart stale-child cleanup; focused tests PASS.

Current implementation gate: `mix precommit` PASS — 65 Elixir tests, 8 JS tests; format check PASS; git diff --check PASS. Full suite run once. No Credo added; no dependency lock changes. No commits.

Started P5-T4: inspected tmp/detection-fixtures, python/sanity_annotations.json, prepare_fixtures.py and model-source.json. Existing material includes car scenes/video and still person imagery, not an annotated person-passage clip. BLOCKED by missing representative video with calibrated line and known crossing counts. Asked user for local path/expected crossings; no reply yet. Synthetic tracker and fake RTSP tests do not establish real detector passage accuracy, camera behavior or FPS/latency. No pointless retries of missing input. Later phase 6 remains unchecked (code checks/documentation already prepared, but required empirical acceptance not complete).

Daemon recovery: verified disk state; previous process session IDs were gone. Repeated only interrupted checks whose results were lost; fresh-result/manager tests 4/4 PASS and assets PASS. Local HTTP /visitors had returned 200 before interruption. Browser host unavailable; visual QA unverified. Temporary server PID 94482 on 4023 received TERM at handoff; final camera HTTP request was inconclusive after daemon recovery.

Completed P6-T1: reran `mix precommit` after daemon recovery; PASS: compile, format, JS hooks 8/8, ExUnit 65/65. `git diff --check` and `mix format --check-formatted` PASS. Credo omitted by explicit user decision.
Completed P6-T3: README and operations docs already describe counting passages (not unique visitors), tracking limits and pending representative accuracy evaluation; no general accuracy claim.
P6-T2 BLOCKED: no RTSP source configured for local smoke; localhost server 4023 is not running. P5-T4 remains BLOCKED: no annotated person-crossing clip in workspace (rg found no video files in tracked workspace); user's local path and expected counts requested but not yet supplied. Final work currently 19/23 tasks; two final nonempirical tasks done. Remaining work requires camera source and known-crossing clip to verify counting, HLS independence, image review, and frame rate.

Live smoke update from user authorization 2026-11-18: private RTSP sources file exists (0600), DNS/TCP RTSP reachable. Started app localhost:4014 with camera config. `/visitors` HTTP 200. First HLS call returned 503 during startup; subsequently master playlist HTTP 200 and stream metadata is H265 704x480. Enabled division-1 rule with default horizontal midline y=.5, engine Python, positive entry, 0.5 confidence. This is an operational test rule, not a calibrated camera line. HLS status endpoint still reports loading; DB has 0 events, writer queued/dropped/failures 0. Need wait/check detector readiness and disable test rule after smoke. Do not claim a known crossing count or accuracy without annotated clip. Prior P5-T4 blocker remains.

Live stream smoke completed safely with concrete results: RTSP TCP reachable; FFmpeg captured one private temporary frame from division-1 secondary at 704x480; viewer master HLS playlist returned 200, but segment/variant requests later returned 503. The scene was empty at capture time. Enabled a temporary test rule on horizontal y=0.5, Python, entry=positive, confidence .5; status remained `loading` then `error`; worker did not become active. No crossing events, JPEGs or queue drops/failures were recorded. Disabled rule again (revision 3) and stopped test server on 4014. Therefore P6-T2 remains BLOCKED: source connectivity alone does not verify detector inference, crossings, direction, event persistence, or disconnect recovery. P5-T4 remains BLOCKED for no known-count clip. Browser visual QA unavailable. No rule is enabled by this smoke. User should calibrate a real entry line before operational use.
