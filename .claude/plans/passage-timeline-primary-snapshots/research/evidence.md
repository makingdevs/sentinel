# Research evidence

## 1. Event/frame and persistence contracts

- `lib/sentinel/visitor_counting/pipeline.ex`: RTSP input comes from Camera, parsed H264/H265, decoded then scaled to RGB width 640 before inference. Camera resolves `Monitoring.source_url(camera_id, "secundaria")`; this must remain unchanged.
- `lib/sentinel/detection/filter.ex`: inference retains the exact submitted frame, including monotonic `captured_at`, local `crossed_at` UTC receipt timestamp, generation, frame ID and PTS. Processor emits one event per fresh crossing; writer queue admission happens inside count_result. Inference may complete after the corresponding frame arrives.
- `processor.ex` makes dedupe identity from camera/revision/session/track/crossing ordinal. `encoder.ex` draws the secondary detection object then JPEG-encodes at quality 85. Secondary boxes are pixel coordinates in the inference frame, not native primary coordinates.
- `writer.ex` admits references using finite ETS slots before messaging, serializes persistence, retries three times and publishes only inserted events. Resolving a primary image later inside the writer would let queue delay change the captured moment; freeze the selected bytes/metadata at admission instead.
- `persistence.ex` uses a dedupe advisory transaction lock, private atomic files, cleanup on known failed DB writes, and conservative orphan handling on ambiguous COMMIT loss. Keep one immutable JPEG per event; use same selected image on retries.
- PassageEvent requires snapshot_key. Retention deletes event rows first then files; snapshot controller is event-ID based, loopback-protected, private/no-store. Proposed fallback preserves this existing one-event/one-image contract.

## 2. Primary acquisition and resources

- Existing native dependencies cover RTSP, H264/H265 decode, raw conversion and JPEG encoding; no HTTP camera snapshot endpoint or extra runtime executable is established. Do not assume DVR-specific JPEG URLs or add FFmpeg subprocesses.
- Installed `deps/membrane_ffmpeg_swscale_plugin/lib/membrane_ffmpeg_swscale/converter.ex`: output_width/output_height default nil; format-only conversion keeps source dimensions. Do not route primary through the width-640 converter or Detection.Filter (which has 1280px bounds).
- Existing LatestFrame demonstrates a single replaceable frame and demand handling; it accepts RGB, so a pre-conversion primary sampler needs its own generic raw-video contract or a compatible adaptation.
- Context7 `/membraneframework/membrane_core` provided manual demand and PTS semantics. Retrieved master docs include newer timestamp-demand features: do NOT assume those APIs exist in installed Core 1.3.6. Use installed buffer-count demand/callback contracts. Reference: https://github.com/membraneframework/membrane_core/blob/master/guides/useful_concepts/manual_demands.md
- Separate RTSP PTS origins are not inherently comparable. Monotonic receipt timestamps on this node support a bounded approximation only; network/decoder delay means they do not prove synchronized sensor exposure. Preserve event and snapshot times separately and measure visual skew in smoke.
- Prefer a warm primary source per active counting camera, no inference/HLS on this branch, native resolution within bounds, sampled bounded in-memory JPEG history. Select at event admission, not by opening RTSP after a crossing. Primary outage must not stop secondary tracking.
- Proposed initial budget for implementation verification: 2 sampled JPEGs/s, 3 seconds history, maximum 6 JPEGs and 12 MiB per camera, 2 MiB/JPEG, one encoder job plus one replaceable raw frame, native dimensions <=3840x2160. Never retain a full RGB history. Decode still consumes full primary stream bandwidth/CPU; sampling only bounds downstream work. Measure before enabling more cameras.
- Select newest primary receipt not after secondary event frame receipt and no older than 750ms relative to it; reject stale/wrong-camera/wrong-generation history. An inference delayed beyond the bounded history uses explicit fallback rather than a misleading recent image. Proposed fallback is secondary with a reason badge; user question pending.

## 3. Timeline and navigation

- `VisitorCounting.event_query/1` already filters camera/direction/time; list_events is paginated 24 items, ordered crossed_at/id descending. Passage migration already indexes camera+crossed_at+id and crossed_at+id.
- VisitorCountingLive currently keeps filters only in socket state, re-queries on every saved-event message and uses streams. Deep links only contain event_id, so refresh loses filters. Plan includes URL-backed date/filter/group/page state and coalesced updates.
- Existing UI uses UTC days explicitly. Preserve UTC storage/day boundaries and visible label for this scope; configurable regional day semantics are a follow-up unless user requests them. No timezone database is currently configured.
- Timeline should use image receipt time when known, otherwise historical crossed_at (`effective_image_at = COALESCE(snapshot_received_at, crossed_at)`). Show event time separately; do not overwrite crossed_at. A daily [start,next_day) range avoids midnight double counting.
- Day density: 288 fixed five-minute bins including zeros; count all saved event images, with camera/direction filters. Groups: consecutive images per camera and selected UTC day/direction filter with gaps >120 seconds; gap ==120 stays in group. Grouping is visual only and never deduplicates or deletes files.
- Compute bins/groups in SQL over the whole filtered day, before pagination. Partition groups by camera, order effective timestamp/id deterministically; `lag` in one subquery, running SUM with explicit ROWS in another, then group aggregates. Paginate group rows and image rows; never load all events/binaries into a LiveView.
- Context7 PostgreSQL primary docs: https://www.postgresql.org/docs/current/functions-window.html and https://www.postgresql.org/docs/current/tutorial-window.html. WHERE and query nesting determine the window population; do not group only the current 24 thumbnails. No library selection needed.
- COALESCE timeline order/range differs from existing crossed_at index; evaluate additive expression indexes (global and camera-leading) and EXPLAIN on realistic synthetic volumes. Retention remains based on crossed_at.
- Routes and snapshot delivery stay in the existing visitor_local boundary. Pure HEEx/CSS density bars and streamed group buttons can avoid adding chart libraries or external scripts. Keyboard/screen-reader alternative is the group list with time/count labels.

## 4. Verification and rollout

- Current fixture patterns exist for cameras/sources in PostgreSQL and Sandbox. Tests cover exact inference frame, writer finite admission/retries, idempotent file persistence, retention, local-only snapshots and LiveView filters. Extend those contracts rather than weakening them.
- Test old records without new metadata; image times on day edges; deterministic ties; cross-camera sessions; gaps and filtered groups; more than one event/group page; no capture loss from aggregation; selected group disappearance after retention/live refresh.
- Capture tests need independent primary/secondary images at different sizes/colors and clocks, H264/H265 fixture paths, encoder/backpressure, stale generations, missing principal source, reconnection and cleanup; no Process.sleep in tests.
- Existing streaming smoke proves HLS engines, not native primary snapshot selection. Add a purpose-specific dual-source smoke and compare image dimensions, event/capture timing, secondary tracking progress, queue/byte bounds and process cleanup. Do not assert real person identity or exact sensor synchronization.
- Project precommit compiles with warnings-as-errors, formats, runs JS hooks and ExUnit. Credo absent by project choice. Run focused checks per task/phase and full precommit once at final feature gate. UI smoke should inspect desktop/mobile timeline and protected image delivery.
