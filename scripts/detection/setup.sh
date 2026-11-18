#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3.12 -m venv .venv
.venv/bin/python -m pip install --require-hashes -r python/requirements.lock
mkdir -p tmp/ultralytics models
export YOLO_CONFIG_DIR="$PWD/tmp/ultralytics"
.venv/bin/python python/setup_models.py
mix deps.get
if [[ "$(uname -s)" == Darwin ]]; then
  export CXX="${CXX:-c++} -Wno-missing-template-arg-list-after-template-kw -Wno-invalid-specialization"
fi
mix compile --warnings-as-errors
