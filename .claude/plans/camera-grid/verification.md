# Verification — cycle 1

Commands executed after the final application/test edits:

- `mix test test/sentinel/monitoring_test.exs test/sentinel_web/live/camera_live_test.exs`: PASS, 10 tests, 0 failures.
- `mix precommit`: PASS, exit 0. Output: `15 tests, 0 failures`.
- `mix format --check-formatted`: PASS, exit 0, no output.
- `mix compile --warnings-as-errors`: PASS, exit 0, no output.
- `mix assets.build`: PASS, exit 0. Tailwind v4.3.3 completed in 147ms; esbuild generated app.js (339.0kb) in 22ms.
- `git diff --check`: PASS, exit 0.

Mix help was consulted before the tasks. Mix required escalation because the
sandbox denied its local PubSub socket. PostgreSQL-backed project suite ran via
the existing alias. No Credo dependency exists, so none was added/run.

One initial focused test failed: a redundant LazyHTML tree count returned zero.
Direct iframe assertions already passed; the assertion was replaced with a
selector excluding a third card. The focused rerun and complete suite passed.

Native Chrome smoke check: initial empty state, add cameras from both branches,
change quality, remove, clear. Retry was clicked; no accessibility-tree change
was expected or taken as proof of successful reconnection. Screenshot inspected:
dark wide layout and 16:9 card, with HTTPS connection error inside iframe.

Public endpoint: curl HTTPS exit 35; Python/OpenSSL WRONG_VERSION_NUMBER.
HTTP HEAD returned 404 with Server: mediamtx. Local resolver succeeded outside
sandbox. No off-VPN, codec, certificate, Safari/mobile, DOM identity/Network or
8-camera throughput claim is supported. These checks remain required.


# Membrane adaptation — cycle 2

After the final source edits:

- `mix precommit`: PASS, 25 tests, 0 failures (3.6s), exit 0.
- `mix format --check-formatted`: PASS, exit 0.
- `mix compile --warnings-as-errors`: PASS, exit 0.
- `mix assets.build`: PASS; Tailwind 124ms, bundled app.js 1.5MB unminified, esbuild 58ms.
- `npm test --prefix assets`: PASS, 5 tests, 0 failures.
- `git diff --check`: PASS.
- `mix hex.audit`: PASS, "No retired or security advisory packages found".
- Quick release-metadata check of 47 changed/new Hex packages: no advisories,
  retirements or request errors returned; `.claude/deps-audit/last-run.json`.
  Full eight-rule supply-chain audit was NOT run; mix_audit/osv-scanner absent.
- npm installation audit: 0 vulnerabilities.

Real source evidence: ffprobe with TCP reports HEVC, 704x480 for the known
División secondary RTSP. Sentinel generated a 200 master manifest containing
hvc1 and local video track URLs. Chrome/macOS screenshot showed the actual
camera image in the new video element at localhost:4012/cameras. The browser
used same-origin HLS; MediaMTX was the upstream RTSP relay in this test.

Earlier dependency attempts failed due to Req and Ratio/Decimal constraints;
the final resolution retains Ecto/Decimal versions and tests Ratio Decimal
interoperability. Upstream compilation emitted deprecation/type warnings;
application warnings-as-errors gate passed without suppressing them.

No real eight-camera load, Safari/mobile, off-VPN, public Sentinel HTTPS,
physical-source interruption or DOM/Network-identity measurement was performed.
The test runner simulates the Membrane boundary for deterministic concurrency,
watchdog, cleanup and reconnect tests; those do not prove actual RTSP recovery.
