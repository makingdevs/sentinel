#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export MIX_ENV=prod
export DATABASE_URL="${DATABASE_URL:-ecto://postgres:postgres@localhost/sentinel_benchmark}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-local-benchmark-only-local-benchmark-only-local-benchmark-only-local-benchmark-only}"
if [[ "$(uname -s)" == Darwin ]]; then
  export CXX="${CXX:-c++} -Wno-missing-template-arg-list-after-template-kw -Wno-invalid-specialization"
fi
if [[ "${1:-}" == --profile-render ]]; then
  exec mix run --no-start scripts/detection/profile_render.exs
fi
.venv/bin/python python/prepare_video.py
exec .venv/bin/python python/benchmark.py "$@"
