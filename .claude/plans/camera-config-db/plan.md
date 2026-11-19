# Persist camera connection configuration in PostgreSQL

## Goal

Persist the camera catalog and each camera's `principal` and `secundaria` RTSP connection in PostgreSQL. Keep camera reads behind `Sentinel.Monitoring`, and use the current private source JSON as seed input so live stream endpoints do not enter version control. Application runtime must no longer depend on `CAMERA_RTSP_SOURCES_FILE` once the database is populated.

## Scope and decisions

- Keep descriptive camera metadata separate from connection details: `cameras` stores the existing camera ID, branch, and label; `camera_sources` stores one URL per camera and quality.
- Use existing camera IDs as string primary keys. `camera_sources.camera_id` references `cameras`; enforce one source per `(camera_id, quality)` and allow only the two current quality names.
- Seed current connections by reading the local file selected by `CAMERA_RTSP_SOURCES_FILE`. Seed reruns are idempotent and update only explicitly selected fields. Do not log or commit source URLs.
- Keep `Sentinel.Monitoring` as the only API for listing cameras and resolving sources. HLS and counting pipelines continue to use that API.
- No camera CRUD UI, app-level URL encryption, or changes to historical visitor-counting IDs are in scope. Database access and backups contain sensitive stream endpoints and need appropriate operational access controls.
- Existing `paths` metadata in the app config appears unused; confirm references during implementation and remove it with the static catalog if still unused.

## Phase 1: Database model and migration [COMPLETED]

- [x] [P1-T1] [ecto] Add `Sentinel.Monitoring.Camera` and `Sentinel.Monitoring.CameraSource` schemas, with a string camera ID primary key and the camera/source association. — String primary key, has_many/belongs_to; URL field redacted.
- [x] [P1-T2] [ecto] Add a migration for `cameras` and `camera_sources`, including the foreign key, unique `(camera_id, quality)` index, allowed-quality check, and non-empty URL check. — Generated timestamped migration; string FK, uniqueness and quality/nonempty checks.
- [x] [P1-T3] [ecto] Add changeset validations for required camera metadata and RTSP URLs with `rtsp` scheme and a host; translate database uniqueness/FK constraints into changeset errors. — RTSP scheme/host validation and translated FK/unique errors; camera_id set on struct.
- [x] [P1-T4] [ecto] Keep the schema aligned with existing string camera IDs used by visitor-counting rules and events; do not rewrite historical records or add a history migration. — Existing visitor rules/events left intact; schema tests preserve division-1 string ID.

## Phase 2: Seed import and Monitoring cutover [COMPLETED]

- [x] [P2-T1] [monitoring] Implement a seed importer that reads and validates the JSON path from `CAMERA_RTSP_SOURCES_FILE`, pairs the eight existing catalog records with their two source qualities, and gives actionable errors for missing/invalid input without printing URLs. — Seed-only catalog; validates all eight pairs before transaction; safe input errors.
- [x] [P2-T2] [monitoring] Make seed reruns safe with explicit conflict targets and field lists. Upsert current camera/source rows without deleting rows absent from the input. — Explicit replace lists preserve source IDs and insertion timestamps; no deletes.
- [x] [P2-T3] [monitoring] Replace configuration-backed implementations of `list_cameras/0`, `camera_options/0`, `fetch_camera/1`, and `source_url/2` with Repo-backed reads while preserving their current return shapes and safe missing-source behavior. — Metadata projections preserve map shape; source query server-only with safe DB failure states.
- [x] [P2-T4] [monitoring] Remove the static camera catalog and runtime `sources` loading from app config after all consumers use the database. Retain unrelated HLS configuration and remove file-path defaults from runtime startup scripts if no longer needed there. — Removed unused paths/catalog and runtime JSON loading; smoke now resolves through Monitoring.
- [x] [P2-T5] [monitoring] Preserve server-only handling and log redaction for RTSP URLs; do not include source values in LiveView assigns, HLS responses, or error messages. — URL schema redaction, SQL log suppression and safe errors verified by focused tests.

## Phase 3: Test, rollout, and verification [COMPLETED]

- [x] [P3-T1] [testing] Convert config-swapping tests in Monitoring, HLS controller, visitor manager, and detection stream isolation to SQL Sandbox-backed camera/source fixtures; update camera LiveView coverage to use persisted cameras. — Added Sandbox catalog/source fixtures to all consumers, including concurrent stream tests.
- [x] [P3-T2] [testing] Cover both qualities, missing camera/source, malformed seed input, URL redaction, and idempotent seed reruns that update configured fields without duplicate records. — Seed, missing-data, privacy and timestamp/identity preservation tests pass.
- [x] [P3-T3] [testing] Verify HLS playback and continuous counting resolve the selected source from PostgreSQL, preserving existing public response behavior and safe failure states. — HLS both qualities verified; counter reconnect reads updated source and handles missing source.
- [x] [P3-T4] [docs] Document bootstrap and deployment order: apply migrations, provide the private JSON for the seed run, run seeds per environment, then start/upgrade the app without the JSON runtime variable. Include that the JSON remains local/private and must not be committed. — README and operation docs describe per-environment migration/seed/start sequence.
- [x] [P3-T5] [verification] Run focused tests, `mix precommit`, and the project's existing streaming smoke procedure against a seeded database; address any failures before handoff. — precommit: 73 Elixir + 8 JS tests pass; local seed 8/16; normal restart ignores JSON; real off/python/elixir smoke each generated 12 HLS segments.

## Acceptance criteria

- Camera metadata and both qualities for the current eight cameras are persisted by the seed workflow.
- HLS and continuous counting resolve RTSP sources from PostgreSQL through `Sentinel.Monitoring` after application restart, without reading the JSON at runtime.
- Re-running seeds creates no duplicates, updates only declared fields, and does not remove unrelated database rows.
- Invalid/missing camera sources fail safely; RTSP endpoints never appear in browser payloads or ordinary logs.
- A fresh environment can follow the documented migration and seed sequence.

## Risks and rollout notes

- Stream URLs identify live camera feeds even without embedded credentials. Keep the seed input private and avoid printing values in errors or logs.
- A database without seed data can start but cannot provide RTSP sources; deployment must seed before enabling camera workflows.
- Runtime database availability now affects camera discovery and stream startup. Confirm supervision/startup behavior and preserve safe handling of Repo errors.
- Tests that currently replace application configuration will need isolated DB fixtures to avoid leaking source values across async tests.
- Decide explicitly in implementation whether missing `CAMERA_RTSP_SOURCES_FILE` should make the seed task fail (recommended for bootstrap correctness) while normal app startup remains independent of it.
