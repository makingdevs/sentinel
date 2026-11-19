# Camera connection configuration in the database

## Research tracks

- [x] Ecto schema, migration constraints, and seed conventions
- [x] Current camera catalog, private RTSP source file, and data sensitivity
- [x] Runtime consumers and context boundary for resolving sources
- [x] Test, deploy, and migration risks for switching from file to DB

## Decisions and dead ends

- Preserve the public camera catalog/labels separately from private connection details unless research shows they must be unified.
- Do not copy or print private RTSP URLs or credentials into research notes.
- Seed RTSP values from the existing local JSON named by `CAMERA_RTSP_SOURCES_FILE`; do not commit stream endpoints because host/path identify live feeds even without embedded credentials.
- Keep all camera reads behind `Sentinel.Monitoring`; do not add a UI or new configuration management surface in this plan.
- Research is complete. No dead end: no Tidewave runtime connector is available, and this plan can be based on source/config/test inspection.

## Implementation decisions (2026-11-19)

- Catalog bootstrap lives only in Monitoring.SeedImporter; runtime reads plain metadata projections from PostgreSQL so CameraSource associations/URLs cannot enter LiveView cards.
- Missing CAMERA_RTSP_SOURCES_FILE fails seed execution; normal boot ignores the variable entirely (verified even with nonexistent path).
- Source inserts/upserts/reads disable SQL logging. URL fields use schema redaction. Import errors never include file contents, paths or supplied URLs.
- Reuse Sandbox catalog/source fixtures for all camera consumers, including monitoring_stream_test concurrent readers (missed initially; full precommit exposed ownership failures and fix passed).
- Preserve existing scope-free Monitoring API as required by this plan; no authentication/scope API redesign or historical event migration.
- Credo is not installed and existing project docs explicitly preserve that choice; verification uses project precommit rather than adding tooling.

## Completion evidence

- 14/14 tasks complete; precommit 73 Elixir and 8 JS tests pass.
- Local DB seeded with 8 cameras/16 sources; restart resolves sources without reading JSON.
- Real streaming smoke without JSON variable exited 0: off/python/elixir each produced 12 HLS segments; detectors active.
- No source URLs copied into tracked files or notes. Existing unrelated .DS_Store and .tool-versions left unchanged.
