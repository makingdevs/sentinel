# Daily image activity timeline and primary-quality crossing snapshots

Status: COMPLETED — implementation verified. Primary remains opt-in pending observation of a real crossing and visual skew before broad rollout.
Depth: deep. Research: [evidence](research/evidence.md). UI/system map: [breadboard](breadboard.md).

## Goal

Identify image activity and temporal groups throughout a selected day without reducing the necessary number of stored crossing images. Continue all detection, tracking, geometry and counting on the secondary RTSP source, while new event JPEGs preferentially come from the native-resolution primary source.

## Scope and proposed defaults

- Extend the current local-only `/visitors` history; keep the existing range view and add an explicit daily timeline mode. No new authentication model, camera CRUD, recognition, event deduplication changes or deletion policy.
- Grouping means temporal activity, not groups of people or identity. One saved event/image stays one saved event/image even if several share a primary frame.
- Proposed daily semantics: UTC, matching current filters. Store all timestamps in UTC. Five-minute density bins (288/day); per-camera groups start after a gap **greater than 120 seconds**. Parameters are bounded server configuration, not arbitrary client SQL intervals. UTC/local-day preference and gap can be adjusted in plan review; regional timezone conversion is not silently introduced.
- Primary capture is a separate warm RTSP decode path per active canonical counter. Native dimensions are preserved within explicit safety limits; no primary inference, HLS encoding, or 640px rescaling. Resolve both qualities only through Monitoring/PostgreSQL.
- Primary snapshots use full frame without the secondary detection rectangle. Keep bbox/confidence/track identity as secondary tracking metadata; do not mislabel the primary image as independently detected or reproject boxes across unverified encodings/crops.
- **Fallback confirmed by user:** is the exact inferred secondary image with a visible fallback reason when primary is missing, stale, over budget or unavailable. This preserves the existing mandatory-image event contract. User confirmed this policy before implementation; an event-without-image policy would require explicit schema/controller/retention changes.
- The event timestamp remains `crossed_at`. New optional provenance records actual image receipt time, channel, dimensions and safe fallback reason. Receipt-time matching approximates the crossing moment; it is not synchronized camera exposure.

## Architecture and contracts

### Timeline

Use `effective_image_at = COALESCE(snapshot_received_at, crossed_at)` for density/group membership; historical records remain visible without file rewrites. A selected UTC day is `[00:00, next-day 00:00)`. Separate event time and image time in detail. Filter camera/direction/day **before** histogram/window calculations and paginate **after** computing groups across the full selected population.

SQL stages: filtered events -> lag(effective time) partitioned by camera, ordered time/id -> mark first/gap >120s -> cumulative sum with explicit ROWS -> grouped count/min/max/anchor -> page. Never merge separate cameras into one group. Histogram and group counts represent saved images; no per-frame rows are synthesized. Selected group image query includes camera + validated group membership/bounds; keyset/order includes ID for tied timestamps. Aggregate-only payloads, paged group stream and existing paged image stream keep LiveView memory bounded.

URL state carries mode/day or legacy range, camera, direction, selection, pages and detail context. Invalid params preserve a safe known state. Selection is validated server-side against current aggregates; retention or late events can merge/remove a group. Preserve a fixed selected interval during live refresh and explicitly reconcile invalid selections. Coalesce PubSub bursts into one pending refresh timer (initial target <=1 refresh/second), never one asynchronous query per event. Retention changes must become visible through a bounded refresh/notification path as well as new-event notifications.

### Image acquisition and ownership

Introduce project-owned SnapshotSource/Pipeline/Sampler/Selector boundaries under VisitorCounting. Canonical Camera lifetime owns one source subscription; the primary acquisition process monitors owner termination and clears cache on disconnect/restart/format change. Supervise long-lived processes and isolate primary failures from secondary Camera/tracker state. Reconnect with bounded backoff and expose capture health separately from counting health. Starting HLS viewers does not create these snapshot readers.

Decode H264/H265 at native dimensions, sample before avoidable RGB conversion/JPEG work, and use explicit demand/latest-frame dropping to bound all queues. Initial tunable budget to verify: 2 JPEGs/s, 3-second history, <=6 JPEGs and <=12 MiB per camera, <=2 MiB/JPEG, <=3840x2160 input, one encoding operation and one replaceable raw frame per camera. Oversized frames fail explicitly; do not silently downscale them and call them native resolution. No full-RGB history, uncontrolled casts/tasks, disk writes in media callbacks, or infinite demand queues. Full primary decode still adds CPU/network cost; measure actual RSS including native buffers.

At finite writer admission, perform a bounded nonblocking cache lookup and freeze the newest primary JPEG whose receipt is not after the event's original secondary frame receipt, with age <=750ms relative to that frame. Compare same-node monotonic receipt timestamps, not independent RTSP PTS origins or writer execution time. Reject other-camera and expired primary/cache generations. Missing history after slow inference uses the chosen fallback. Admitted immutable bytes/provenance survive retries even if the live source reconnects later. Release unused secondary payload references when a primary image is selected.

Reuse Persistence.save, event dedupe key, private atomic JPEG handling, commit-before-PubSub and finite writer admission/retries. Store one image artifact per event; no persistent cache frames, duplicate event files per retry or historical recapture. Source URLs and image binaries never enter LiveView assigns, navigation params or logs.

### Additive data changes

Add optional `snapshot_quality`, `snapshot_received_at`, `snapshot_width`, `snapshot_height`, `snapshot_fallback_reason`, and explicit secondary tracking dimensions if bbox consumers require them. Use known enum/check constraints and validate provenance as trusted internal data. Historical rows render as secondary historical capture with unknown dimensions/receipt time where absent; do not invent them. Keep snapshot_key required under the proposed fallback policy.

Add appropriately measured expression indexes on effective_image_at and `(camera_id, effective_image_at, id)` if query plans require them; existing crossed_at indexes remain for retention/history. Use mix ecto.gen.migration and review table-lock impact on a populated database. Plan an additive deploy: migrate first, deploy compatible readers/writer, enable primary capture gradually. No history file rewrite.

## Phase 1: Metadata and timeline queries [COMPLETED]

- [x] [P1-T1][ecto] Add backward-compatible snapshot provenance schema/migration and fixture defaults, with valid quality/reason/dimension checks. Keep historical snapshot_key/dedupe/retention contracts intact. Verify old rows and native primary/secondary fallback metadata round-trip. — Nullable provenance with SQL/changeset checks; context round-trip tests pass.
- [x] [P1-T2][ecto] Add VisitorCounting timeline APIs for validated one-day bounds, zero-filled density bins and per-camera gap groups using staged SQL windows; add group/selected-image pagination and validated selection. Reuse the same effective-time/filter semantics across all APIs. Test midnight, exact gap boundary, ties, interleaved cameras, direction filters and datasets exceeding 24 images and one group page. — SQL windows, 288 bins, bounded 24-row pages; focused boundary/pagination tests pass.
- [x] [P1-T3][testing] Add realistic synthetic-volume query checks/EXPLAIN, parameterized query/index migration evidence and tests proving totals across all groups match the selected day without loading image files or all events into Elixir. Check retention-visible refresh and additive migration/rollback on disposable test data.

## Phase 2: Bounded primary capture [COMPLETED]

- [x] [P2-T1][otp] Resolve the pending fallback preference and codify snapshot selection/provenance contracts. Add supervised primary-source lifecycle tied to active canonical counters, private Monitoring principal resolution, independent retry/health and reliable cleanup. Secondary tracking source and session behavior remain unchanged. Test primary outage without resetting secondary tracking and owner/source failures.
- [x] [P2-T2][membrane] Implement native-resolution H264/H265 primary decode, bounded sampling/conversion/encoding and immutable JPEG cache with count/byte/age/size limits. Use installed Membrane APIs (not newer master-only timestamp demand). Test real decoders with deterministic fixtures, format changes, slow encoders, drop behavior, no inference on primary and bounded queue/memory ownership.
- [x] [P2-T3][otp] Implement the nonblocking selector at finite admission: match original event-frame receipt time, camera and active cache generation, enforce age and select/freeze bytes/provenance. Cover inference/queue delays, no future/stale images, multiple events sharing a frame, reconnect and fallback. Keep all caches/encoding queues independently bounded before messaging.
- [x] [P2-T4][testing] Integrate selected primary JPEGs with the writer and existing Persistence; retain exact secondary frame annotation only for fallback. Preserve same artifact and timestamp on retries/dedup, cleanup/retention and PubSub ordering. Adapt the fresh-inference-frame tests to assert secondary tracker input plus correctly sourced primary saved pixels/dimensions; never loosen frame identity assertions.

## Phase 3: Timeline and image browsing [COMPLETED]

- [x] [P3-T1][liveview] Add URL-backed daily/range modes and selection state in VisitorCountingLive. Load aggregates/group/image pages asynchronously after connection, cancel/ignore obsolete query results and coalesce updates with bounded timers. Preserve camera/direction/day/group context on pagination, deep-link detail, refresh and Back. Handle invalid/stale selection, empty day and query errors distinctly.
- [x] [P3-T2][liveview] Build a responsive daily density strip with visible quiet spans and keyboard-accessible grouped activity list. Use existing HEEx/function components, Tailwind and unique IDs; stream groups/images and keep counts separately. Selecting a bin/group narrows the image gallery and reset returns to full-day activity. No chart library, inline scripts, source URLs or JPEG binaries in socket state.
- [x] [P3-T3][liveview] Display primary/fallback/historical provenance, dimensions and separate event/image receipt times in image cards/detail. Present native primary image at detail size without claiming secondary bbox alignment; preserve private/no-store snapshot delivery and lazy loading. Keep legacy records and the range view usable.
- [x] [P3-T4][testing] Add LiveView/context/controller coverage for group navigation, >one page, shared timestamps, filter/URL round trips, live bursts, retention/group invalidation, stale async replies, malformed inputs, responsive accessibility affordances and loopback protection. Verify no aggregation changes stored image/event count.

## Phase 4: Integration and rollout [COMPLETED]

- [x] [P4-T1][testing] Add a dual-channel smoke using deterministic secondary crossing and larger primary fixtures, then one controlled real-camera run. Verify secondary tracking continues through primary failure/reconnect, successful captures have principal-native pixels/dimensions, fallback is truthful, timing skew is reported and admitted events remain one image each. Record CPU/RSS/network/queue/cache bounds at supported camera capacity before enabling broadly; do not alter user rules without restoring them.
- [x] [P4-T2][docs] Document grouping semantics/defaults, UTC days, provenance/fallback policy, capture limits, primary bandwidth/CPU cost, disk growth and existing retention. Document migrate/deploy/gradual enable/rollback sequence and what historical images cannot gain. Keep all RTSP values private.
- [x] [P4-T3][verification] Run focused tests per phase, mix format --check-formatted and mix compile --warnings-as-errors per task; run mix precommit as the final full-suite gate. Run the existing streaming smoke for regression, the new capture smoke, and desktop/mobile/keyboard timeline checks. Credo only if already installed (currently absent); record unavailable checks honestly.

## Acceptance criteria

1. Selected-day timeline highlights actual persisted image activity and quiet periods; groups cover all images exactly once within the selected filters, regardless of page size. Camera groups are separate, with time range and image count.
2. Selecting a bin/group opens its paged images; detail and navigation retain date/camera/direction/selection. Existing range filters and historical images remain available.
3. Secondary RTSP remains the sole detector/tracker source. Healthy primary channel produces native-dimension JPEGs near the original event-frame time, with explicit provenance and independent event time.
4. Missing/stale/oversized primary data follows the explicitly chosen failure policy, visible to the user, without blocking/resetting counting or falsely claiming primary/synchronized images.
5. Capture processes, encoder queues, cache bytes, persistence admission and LiveView/query payloads have explicit bounds. Primary readers stop with their canonical counter and are not duplicated by HLS viewers.
6. Existing dedupe, protected image delivery, finite retries, retention and historical files remain correct. Temporal grouping neither suppresses capture events nor deletes their images.
7. Focused tests, full precommit and dual-source/runtime/UI evidence pass or are explicitly recorded as rollout blockers; no private URLs appear in artifacts or browser state.

## Split decision

One plan, four phases: shared provenance/selection contracts make integration review useful. If execution context grows, split after Phase 1 into timeline UI (Phase 3) and capture acquisition (Phase 2), preserving P4 as their integration gate; do not start parallel implementation without agreeing file ownership. No need to re-research existing dependencies.

## Risks and deep self-check

- **What if channel times/encuadres differ?** Receipt-time tolerance is approximate. Separate timestamps and no primary bbox overlay avoid false claims; real visual skew must be measured. Strict sensor-time correspondence would require a separate synchronization investigation.
- **What if high-resolution load overwhelms the server or disk?** Decode cost is not removed by sampling. Enforce queue/byte/dimension limits, isolate primary health, retain existing event admission semantics and stage rollout after measured resource checks. Grouping improves navigation, not storage volume. Larger images keep existing retention and need disk budgeting.
- **What if history is huge, late events merge groups or retention removes images?** Aggregate server-side, use measured indexes and bounded pages/refreshes, validate selections and keep historical fallback time semantics explicit. Never infer full-day grouping from the currently visible thumbnails.

## Deferred

Image deduplication/reduction, person recognition, primary inference, exact camera-clock synchronization, primary bbox calibration, new retention policies, extra persistent thumbnail files, remote auth redesign and regional timezone conversion. None is silently implemented as part of this plan.
