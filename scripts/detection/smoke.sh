#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export CAMERA_RTSP_SOURCES_FILE="${CAMERA_RTSP_SOURCES_FILE:-$PWD/tmp/camera_rtsp_sources.json}"
exec mix run --no-start scripts/detection/smoke.exs "$@"
