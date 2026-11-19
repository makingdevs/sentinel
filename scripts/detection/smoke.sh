#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec mix run --no-start scripts/detection/smoke.exs "$@"
