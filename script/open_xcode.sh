#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/run_backend.sh" --background
open "$ROOT_DIR/BudgetTracer.xcodeproj"
