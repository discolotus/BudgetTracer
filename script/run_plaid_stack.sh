#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/run_backend.sh" --background
BUDGETTRACER_USE_BACKEND=1 "$ROOT_DIR/script/build_and_run.sh" "${1:-run}"
