# Passage timeline and primary snapshots

Depth: deep. Planning only; implementation not authorized by this workflow yet.

## Research tracks
- [x] Existing event/frame ownership, persistence, retry and retention contracts
- [x] Primary-channel frame acquisition, synchronization and bounded resource design
- [x] Timeline queries, timezones, grouping and LiveView navigation
- [x] Verification, rollout and backwards compatibility

## User intent
Keep secondary tracking; capture primary-quality images. Show daily image activity and groups without reducing the necessary image volume.

## Pending clarification
Primary-channel failure policy asked asynchronously; do not finalize dependent fallback behavior until answered.

## Planning decisions
- All selected source/documentation research tracks complete; evidence captured in research/evidence.md.
- Single cohesive plan with independently reviewable timeline and primary-capture phases; no implementation yet.
- Retain UTC day semantics and propose 120-second inactivity grouping, adjustable during plan review.
- Primary failure behavior remains a proposed secondary fallback, explicitly pending user preference; safe planning can describe this default without treating silence as approval.
- Avoid on-demand RTSP connects, primary inference, full-RGB history, cross-stream PTS equality and automatic bbox projection.

## Execution decisions
- User authorized direct execution and exact secondary fallback when primary fails.
- No `.claude/solutions/` directory exists in this checkout.
