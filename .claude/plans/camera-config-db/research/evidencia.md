# Research evidence: camera configuration in PostgreSQL

## Current model and sources

- `config/config.exs` defines eight catalog entries (`division-1..4`, `lavirgen-1..4`) with branch and display label. It also includes `paths` maps, but source search found no runtime use of those fields.
- `tmp/camera_rtsp_sources.json` is ignored by Git and has mode 0600. A metadata-only inspection found all eight IDs and both qualities (`principal`, `secundaria`). The URLs contain no username/password userinfo. The host/path values still identify live streams and must not be copied into this research file or accidentally exposed in logs, LiveView assigns, or a public repository.
- `config/runtime.exs` reads `CAMERA_RTSP_SOURCES_FILE` on boot into `:monitoring, :sources`; if unset, the source map is empty. `scripts/detection/server.sh` and `smoke.sh` supply the local JSON path as their default.
- `Sentinel.Monitoring` owns catalog lookup and `source_url/2`. HLS and `Sentinel.VisitorCounting.Camera` resolve sources through it; the resulting RTSP URL is passed server-side to Membrane. The browser gets same-origin HLS URLs.
- `Sentinel.Monitoring.LogFilter` redacts RTSP URIs. HLS controller tests also assert that source values are not returned to clients.

## Persistence and context conventions

- `priv/repo/seeds.exs` is currently the generated empty seed file. `mix ecto.setup` runs migrations then seeds; `mix test` migrates the test DB.
- Ecto SQL is pinned to `~> 3.13`; current schema coverage uses SQL Sandbox through `Sentinel.DataCase`. The current `Sentinel.MonitoringTest` instead swaps application config and will need database fixtures after the cutover.
- Existing migrations use explicit DB constraints and indexes. Context functions own reads; LiveViews and pipeline consumers call `Sentinel.Monitoring`, rather than querying `Repo` themselves.
- Current Ecto docs describe explicit conflict targets and field-specific upserts. Avoid `:replace_all` for seed updates; explicitly enumerate mutable fields so seed reruns do not reset IDs/timestamps or unrelated data.

## Proposed boundary and transition

- Persist descriptive camera metadata in `cameras` and per-quality RTSP connections in `camera_sources` (`camera_id`, quality, URL), with a camera FK, a unique `(camera_id, quality)` index, and DB checks for allowed qualities/non-empty URLs. Validate `rtsp` scheme and host in the changeset as well.
- The Monitoring context remains the sole read API. It loads cameras from Repo and resolves a source by camera ID + quality. Remove `cameras` and `sources` from application runtime config after consumers switch; retain unrelated HLS directory configuration.
- Seed the existing eight catalog rows and both RTSP qualities idempotently. Prefer importing connection values from the local private JSON at seed time, rather than committing stream endpoints in tracked source. The JSON is needed to bootstrap each environment once; application runtime should not need it after seeding.
- Do not add a camera editing UI or app-level URL encryption in this task. Preserve the no-source-URL-to-browser/log guarantee; access to PostgreSQL and its backups remains sensitive.

## Verification and operational risks

- Update Monitoring, HLS controller, visitor manager, detection stream-isolation, and camera LiveView tests to create DB fixtures inside Sandbox.
- Verify seed reruns update the intended camera/source fields without duplicating rows and without deleting cameras not listed in the seed input.
- Verify both HLS and continuous-counting pipelines resolve each quality from the database, while a missing camera/source returns the existing safe error states.
- Deploy/migrate first, seed the existing sources in each target database, then remove runtime dependency on the JSON file. If seeding fails or is skipped, the app can start but camera sources remain unavailable.
