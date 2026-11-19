#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PORT="${PORT:-4013}"
exec mix phx.server
