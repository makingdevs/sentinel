# Execution progress

Started: P1-T1 — schemas and string camera identifiers.
Context: scratchpad and research read; .claude/solutions does not exist. Source spot-check confirms plan assumptions.

Completed: P1-T1 — format/check and compile --warnings-as-errors passed.
Started: P1-T2 — generated migration with mix ecto.gen.migration.
Completed: P1-T2 — migration generated; format/check and compile passed.
Started: P1-T3 — validations and database constraint translation.
Completed: P1-T3 — format/check and compile passed; URL scheme/host validated, constraint mappings added.
Started: P1-T4 — verify unchanged string IDs and schema constraints with Sandbox tests.
Completed: P1-T4 / Phase 1 — 2 Sandbox schema tests pass; existing visitor IDs unchanged. Credo unavailable (not a dependency); no dependency added.
Started: P2-T1 — seed-only catalog and validated private JSON import.
Completed: P2-T1 — format/check and compile passed; validate entire input before transaction; errors omit values/path.
Started: P2-T2 — explicit upserts preserve original IDs and insertion timestamps.
Completed: P2-T2 — format/check and compile passed; explicit conflict targets and replace lists; no deletes.
Started: P2-T3 — Repo-backed public read boundary; preserve plain metadata maps.
Completed: P2-T3 — format/check and compile passed; metadata-only projections; bounded database errors yield safe states.
Started: P2-T4 — remove runtime/static source configuration and update smoke consumer.
Completed: P2-T4 — config and scripts format/check + compile pass; paths unused; runtime no longer reads private file.
Started: P2-T5 — security boundary checks and focused seed tests.
Completed: P2-T5 / Phase 2 — 6 focused tests pass (seed, schema, log filter); format/check and compile pass. Source queries/writes disable SQL logging; no sources projected into public maps.
Started: P3-T1 — Sandbox fixtures for catalog consumers and streaming tests.
Completed: P3-T1 — format/check and compile passed; 29 affected tests pass, including camera LiveViews, HLS, detection, manager, historical events. First format check caught one file omitted by directory argument; fixed with full formatter.
Started: P3-T2 — negative paths, log redaction and seed rerun coverage.
Completed: P3-T2 — 12 focused tests pass; both qualities, invalid JSON/missing values, empty catalog, redaction, upsert identity/timestamps, unrelated rows preserved.
Started: P3-T3 — verify exact DB-selected sources reach HLS and continuous counting.
Completed: P3-T3 — 9 streaming/counter/isolation tests pass; both HLS qualities use exact DB URLs; counter reconnect reads updated source and absent source gives error.
Started: P3-T4 — bootstrap/deployment documentation.
Completed: P3-T4 — README, monitoring, detection and counting docs updated; format/check + compile pass.
Started: P3-T5 — precommit final full-suite gate, local DB migration/seeding, streaming smoke without JSON runtime variable.
P3-T5 attempt 1: precommit JS 8/8 passed; ExUnit 73 tests, 2 failures. Root cause: MonitoringStreamTest also required Sandbox conversion. Converted remaining config fixture.
Local mix ecto.migrate: migrations already up.
P3-T5 attempt 2: mix precommit PASS — 73 ExUnit tests, 0 failures; 8 JS tests, 0 failures; compile --warnings-as-errors and format passed. Local seed PASS — 8 cameras, 16 sources. Real smoke running with CAMERA_RTSP_SOURCES_FILE removed from environment.
Local restart smoke PASS — normal mix run with nonexistent CAMERA_RTSP_SOURCES_FILE starts, lists 8 persisted cameras and resolves source. Streaming off and python both emitted hls_ready with 12 segments each; python active. Elixir pending.
Completed: P3-T5 / Phase 3 — existing real streaming smoke exited 0 without CAMERA_RTSP_SOURCES_FILE: off hls_ready/12 segments; python active+hls_ready/12 segments; elixir active+hls_ready/12 segments. Results under ignored tmp/detection-smoke/{off,python,elixir}/result.json. Native colorspace/XLA informational messages only. git diff --check passed.

COMPLETE: 14/14 tasks, 3 phases. No commits made. Full precommit passes; no additional full-suite run needed after documentation/checkpoint-only edits. Real smoke verifies selected source and all three engines, not all eight cameras/both qualities in every browser. Continuous counter source/reconnect covered by focused integration tests; no rule settings changed for smoke.
Other pending plans (not started): camera-grid (5), personas-autos (2), visitor-passes (2).
