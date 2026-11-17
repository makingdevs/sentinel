# Read-only review — cycle 1

Verdict: REQUIRES CHANGES (operational requirements remain unmet).

Scope: current worktree against HEAD, including new untracked Monitoring,
CameraLive, template, tests, deployment overlay and documentation. Review was
sequential; no application or test edits were made in REVIEWING.

Requirements coverage:

- Catalog, ID/quality validation, HTTPS-only public URLs: implemented and tested.
- Eight-camera selection, deduplication, remove/clear, individual quality/retry:
  implemented, focused suite and full suite pass.
- Stream DOM IDs, responsive layout, accessible iframe titles and controls:
  implemented; native Chrome smoke checked. Actual node/network preservation
  remains unverified; stable markup IDs are not browser identity evidence.
- Public HTTPS playback, codec/browser compatibility and load: UNMET.
- Verification: local checks PASS; complete operational acceptance pending.

Findings:

1. BLOCKER — docs/monitoring.md:66; plan.md:43. HTTPS endpoint fails TLS in
   curl and Python/OpenSSL and the real iframe shows a connection error. The
   acceptance criterion of Internet HTTPS playback cannot be met until server
   HTTPS is configured and validated. Apply the prepared overlay after confirming
   installed version, server access and DNS/ACME ownership. Existing infra tasks
   remain open; do not infer missing certificate as the definitive cause.
2. WARNING — docs/monitoring.md:75. Off-VPN Safari/mobile playback, codecs,
   iframe node identity/Network behavior and eight-camera load have no evidence.
   Complete existing phase-3 tasks after TLS is operational. These are validation
   gaps, not demonstrated defects in the local implementation.

No additional code defects found in the reviewed scope. Inputs are allowlisted;
no source URLs/credentials are copied into application configuration or HTML;
no Ecto queries, new dependencies, authentication or API exposure were added.
Default layout behavior remains available with wide=false. Full project suite:
15 tests, 0 failures.

Next action: obtain server/DNS access, resume existing infra and phase-3 plan
items in WORKING, then repeat VERIFYING and read-only REVIEWING. COMPOUNDING
is not entered because full verification/accepted review gates are incomplete.


# Membrane adaptation — cycle 2 read-only review

Scope: current adaptation against the previous iframe implementation, including
all new backend, HLS delivery, frontend, tests and runtime config. Sequential
review; no source/test edits made after VERIFYING PASS.

Local adaptation verdict: PASS WITH WARNINGS. No additional code defects found.
Full original public-deployment acceptance verdict: INCOMPLETE / REQUIRES CHANGES.

Checked: allowlisted IDs/qualities/files, no user-defined RTSP URLs, private
runtime sources, source-URL log redaction, supervised shared workers and start
races, pipeline failure handling, source stalls and inactivity, atomic resource
publication, HLS MIME and no-cache policy, generation isolation, per-player hook
teardown/retry/native fallback, input validation and original grid interactions.

Evidence: 25 ExUnit tests and 5 JS tests pass; compile/format/assets pass;
actual División secondary RTSP is HEVC 704x480; generated HLS master returned
200 with hvc1 and native Chrome screenshot displayed actual camera video.

Warnings/limits:

- docs/monitoring.md (Códecs): H265 passthrough works in the tested Chrome/macOS
  environment, but some clients require an H264 camera output or a separately
  sized transcoder. No blanket browser compatibility claim.
- docs/monitoring.md (Ciclo de vida): pipelines and files are instance-local;
  clustered deployments need routing affinity or a dedicated shared media tier.
- mix.exs: Req is constrained to 0.6.x by ex_hls. Decimal override bypasses
  Ratio's older optional constraint, with interoperability coverage and real HLS
  generation evidence. Revisit on dependency upgrades. Ecto/Decimal retained.
- Remaining operational plan tasks: public HTTPS for Sentinel, off-VPN,
  Safari/mobile, both sites/eight cameras and measured load. They are not
  established by unit tests or a single working video.

The old MediaMTX HLS TLS blocker is superseded for this architecture: the tested
source uses its RTSP relay, while HLS is served from Sentinel. The application
still requires network reachability to whichever RTSP origin is configured.

COMPOUNDING is deferred because original public acceptance remains incomplete.
No extra code changes requested by this local review.
