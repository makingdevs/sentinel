#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "${1:-}" == "--real" ]]; then
  shift
  exec mix run --no-start scripts/visitors/real_capture_smoke.exs "$@"
fi
exec mix test test/sentinel/visitor_counting/fresh_result_test.exs test/sentinel/visitor_counting/snapshot_decode_test.exs test/sentinel/visitor_counting/snapshot_source_test.exs test/sentinel/visitor_counting/snapshot_selector_test.exs test/sentinel/visitor_counting/writer_test.exs
