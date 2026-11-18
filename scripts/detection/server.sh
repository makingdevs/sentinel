#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export CAMERA_RTSP_SOURCES_FILE="${CAMERA_RTSP_SOURCES_FILE:-$PWD/tmp/camera_rtsp_sources.json}"
export PORT="${PORT:-4013}"
exec mix phx.server
