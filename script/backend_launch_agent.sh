#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-start}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.budgettracer.backend"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$ROOT_DIR/.budgettracer-backend.log"
ERROR_LOG_FILE="$ROOT_DIR/.budgettracer-backend.err.log"
PORT="${BUDGETTRACER_BACKEND_PORT:-8790}"
DOMAIN="gui/$(id -u)"

start_backend() {
  swift build --product BudgetTracerBackend >/dev/null
  APP_BINARY="$(swift build --show-bin-path)/BudgetTracerBackend"
  mkdir -p "$HOME/Library/LaunchAgents"

  /usr/libexec/PlistBuddy -c Clear "$PLIST" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $APP_BINARY" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :WorkingDirectory string $ROOT_DIR" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :KeepAlive bool true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :StandardOutPath string $LOG_FILE" "$PLIST"
  /usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $ERROR_LOG_FILE" "$PLIST"

  launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "$DOMAIN" "$PLIST"
  launchctl kickstart -k "$DOMAIN/$LABEL"

  for _ in $(seq 1 80); do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      echo "BudgetTracerBackend launch agent running on http://127.0.0.1:$PORT"
      exit 0
    fi
    sleep 0.1
  done

  echo "BudgetTracerBackend launch agent failed to become healthy." >&2
  echo "stdout: $LOG_FILE" >&2
  echo "stderr: $ERROR_LOG_FILE" >&2
  exit 1
}

case "$MODE" in
  start)
    start_backend
    ;;
  stop)
    launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
    echo "BudgetTracerBackend launch agent stopped"
    ;;
  status)
    launchctl print "$DOMAIN/$LABEL"
    ;;
  *)
    echo "usage: $0 [start|stop|status]" >&2
    exit 2
    ;;
esac
