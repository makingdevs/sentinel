# Execution progress

Started: P1-T1 — additive snapshot provenance, user confirmed secondary fallback.

Completed: P1-T1 — compile and format checks passed; context tests: 6 tests, 0 failures.
Started: P1-T2 — staged SQL timeline grouping and bounded pages.

Completed: P1-T2 — compile/format passed; timeline tests: 2 tests, 0 failures.
Started: P1-T3 — synthetic volume and query plans.

Completed: P1-T3 — 200,000 synthetic rows, 8,640 images/day, SQL group/bin totals agree; EXPLAIN ANALYZE used effective-time index (observed 6.179 ms execution). Concurrent expression indexes added. Disposable-schema migration/up/down passed for original table + provenance + indexes; no production data touched. Credo absent, as planned.
Phase 1 completed: focused context + timeline tests pass (9 tests); compile and scoped format checks pass.
Started: P2-T1 — confirmed secondary fallback; isolated source lifecycle.

Completed: P2-T1 — source/manager tests: 6 passed, compile and scoped format passed. Primary lifecycle isolated and owner-monitored; PostgreSQL principal resolution. Capture defaults off for measured gradual rollout.
Started: P2-T2 — native decode and bounded sampling/encoding.

Completed: P2-T2 — native H264/H265 generated-fixture decoder/JPEG tests and sampler/cache tests pass (5 tests); format/compile checks pass. Generic raw sampler drops before conversion; no raw history, 2 Hz; cache max 6 JPEG/12 MiB, 2 MiB/image. Format changes rotate cache generation. Resource measurements remain P4 rollout gate.
Started: P2-T3 — nonblocking selection at finite admission.

Completed: P2-T3 — selector edge tests, writer admission/retry and original fresh-result tests passed; compile/format passed. ETS read only; no source calls on admission, generation tied to original inference frame.
Started: P2-T4 — primary pixel provenance and writer integration verification.

Completed: P2-T4 — secondary frame identity assertions preserved for fallback and strengthened on every inference input; primary test asserts independent green native pixels and 800x480 dimensions, no retained secondary payload. Writer retry/dedupe/retention tests pass with provenance. Phase 2 focused suite passed; compile/format passed.
Started: P3-T1 — URL state, bounded refresh and cancellable async queries.

Completed: P3-T1 — URL-backed day/range/filter/page/detail, cancellable named async task, one pending 1s refresh timer and periodic retention refresh. Original LiveView tests adapted to await async work and pass (3 tests); compile/format pass.
Started: P3-T2 — density strip and streamed activity groups.

Completed: P3-T2 — 288 native buttons with quiet bins, streamed group list/pagination and reset. Four LiveView tests pass including >24 groups, selection, detail URL and return. Corrected aria-pressed to explicit string values for accessible state. Compile/scoped format passed.
Started: P3-T3 — visible snapshot provenance in cards/detail.

Completed: P3-T3 — card/detail provenance, explicit receipt/event times, historical unknowns, native full-frame primary detail and private image controller retained. LiveView/controller tests pass; scoped format/compile pass.
Started: P3-T4 — retention invalidation, burst coalescing, URL/malformed/stale result tests.

Completed: P3-T4 — focused context/LiveView/controller phase suite: 20 tests passed. Tests cover burst coalescing, retained URLs, invalid group IDs, group deletion without new events, rapid superseding query changes, primary/fallback/historical rendering and loopback protection. Scoped format/compile pass.
Started: P4-T1 — controlled dual-source/runtime smoke and resource evidence. Tightened manual JPEG sink prefetch to 1, bounded push toilets, source TTL sweep/watchdog, per-camera rollout allowlist; native decoder tests still pass.

Correction: P3-T4 final expanded suite exposed an SQL Sandbox ownership failure when cancelling an in-flight DB task during rapid URL changes. Previous completion entry was premature. Reopened P3-T4; replacing cancellation with one active query and one latest pending refresh, discarding obsolete replies. P4 not started until phase gate passes.

P3-T4 verified after correction: 20 tests, 0 failures; compile/scoped format pass. One active query plus one coalesced pending request; obsolete results ignored.
Started: P4-T1 — dual-channel smoke and real-source resource checks.

Completed P4-T1. Deterministic capture smoke passed (9 tests). Two real cameras decoded native primary JPEGs at 1440 × 1616 and recovered after forced primary reconnect with secondary session IDs preserved and 219/209 processed frames. Over 55.5 seconds, encoded primary ingress was 6.20/5.95 MB; secondary was 2.24/2.23 MB. Final camera caches: 6 images each, 2.24/1.82 MB. Peak sampled process CPU was 199.7% and RSS 438 MiB including native buffers, excluding any external worker process. The real sample saw no crossings, so visual skew and real-crossing primary persistence remain rollout checks. Exact provenance and persistence were verified with fixtures.
Completed P4-T2. Updated docs/visitor-counting.md with UTC grouping, capture and disk bounds, enablement, migrations and rollback.
Started P4-T3. Chrome desktop, 400px viewport and keyboard bin selection verified. Precommit passed with 90 ExUnit and 8 JavaScript tests after fixing a fixture that could straddle UTC midnight. Format and diff checks passed. Streaming regression smoke in progress.

Completed P4-T3. Existing real RTSP streaming smoke passed in off, Python and Elixir modes. All reached HLS readiness and both detectors reached active. Browser desktop, 400 px mobile and keyboard checks passed. Credo absent as documented.

Review follow-up. Secondary startup now proceeds independently and retries primary registration after a collision. Gallery pages load events and pagination in one SQL statement. Malformed list/map selections fall back to the full day. Regression cases passed in precommit (92 ExUnit and 8 JavaScript tests). A coordinated physical crossing is pending to validate persisted primary pixels and visual skew before broader rollout.
