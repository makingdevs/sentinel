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
