#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BudgetTracerBackend"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.budgettracer-backend.pid"
LOG_FILE="$ROOT_DIR/.budgettracer-backend.log"
PORT="${BUDGETTRACER_BACKEND_PORT:-8790}"

stop_backend() {
  if [ -f "$PID_FILE" ]; then
    PID="$(cat "$PID_FILE")"
    if kill -0 "$PID" >/dev/null 2>&1; then
      kill "$PID" >/dev/null 2>&1 || true
      sleep 1
    fi
    rm -f "$PID_FILE"
  fi
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

case "$MODE" in
  run)
    stop_backend
    swift build --product "$APP_NAME"
    APP_BINARY="$(swift build --show-bin-path)/$APP_NAME"
    "$APP_BINARY"
    ;;
  --background|background)
    stop_backend
    swift build --product "$APP_NAME"
    APP_BINARY="$(swift build --show-bin-path)/$APP_NAME"
    nohup "$APP_BINARY" >"$LOG_FILE" 2>&1 </dev/null &
    echo "$!" > "$PID_FILE"
    for _ in $(seq 1 50); do
      if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo "BudgetTracerBackend running on http://127.0.0.1:$PORT"
        exit 0
      fi
      sleep 0.1
    done
    echo "BudgetTracerBackend failed to become healthy; see $LOG_FILE" >&2
    exit 1
    ;;
  --stop|stop)
    stop_backend
    echo "BudgetTracerBackend stopped"
    ;;
  --logs|logs)
    tail -f "$LOG_FILE"
    ;;
  *)
    echo "usage: $0 [run|--background|--stop|--logs]" >&2
    exit 2
    ;;
esac
