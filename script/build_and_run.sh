#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BudgetTracerMac"
BUNDLE_ID="com.budgettracer.mac"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [ -n "${BUDGETTRACER_PLAID_RELAY_URL:-}" ] &&
  [ -z "${BUDGETTRACER_DATA_MODE:-}" ] &&
  [ -z "${BUDGETTRACER_SECURE_LOCAL:-}" ]; then
  export BUDGETTRACER_DATA_MODE="secure-local"
fi

if [ -n "${BUDGETTRACER_APPLE_IDENTITY_TOKEN:-}" ] &&
  [ -z "${BUDGETTRACER_PLAID_RELAY_URL:-}" ] &&
  [ "${BUDGETTRACER_DATA_MODE:-}" != "secure-local" ] &&
  [ "${BUDGETTRACER_SECURE_LOCAL:-}" != "1" ]; then
  cat >&2 <<MESSAGE
BUDGETTRACER_APPLE_IDENTITY_TOKEN is set, but the local app is not configured to use a Plaid relay.

For Cloudflare dev testing, launch with:

  BUDGETTRACER_PLAID_RELAY_URL=<dev workers.dev URL> \\
  BUDGETTRACER_APPLE_IDENTITY_TOKEN=<dev bearer token> \\
  ./script/build_and_run.sh

The script will set BUDGETTRACER_DATA_MODE=secure-local when BUDGETTRACER_PLAID_RELAY_URL is present.
MESSAGE
  exit 2
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
BUILD_PRODUCTS_DIR="$(dirname "$BUILD_BINARY")"
SQLCIPHER_FRAMEWORK="$BUILD_PRODUCTS_DIR/SQLCipher.framework"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -d "$SQLCIPHER_FRAMEWORK" ]; then
  ditto "$SQLCIPHER_FRAMEWORK" "$APP_FRAMEWORKS/SQLCipher.framework"
  if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
  fi
  codesign --force --sign - "$APP_FRAMEWORKS/SQLCipher.framework" >/dev/null
fi

codesign --force --sign - "$APP_BINARY" >/dev/null

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_BUNDLE" >/dev/null

open_app() {
  OPEN_ARGS=(-n -F)
  for variable in \
    BUDGETTRACER_DATA_MODE \
    BUDGETTRACER_SECURE_LOCAL \
    BUDGETTRACER_USE_BACKEND \
    BUDGETTRACER_BACKEND_URL \
    BUDGETTRACER_PLAID_RELAY_URL \
    BUDGETTRACER_ALLOW_INSECURE_LOCAL_RELAY \
    BUDGETTRACER_APPLE_IDENTITY_TOKEN \
    BUDGETTRACER_DEV_SECRET_STORE \
    BUDGETTRACER_DEV_SECRET_STORE_PATH \
    BUDGETTRACER_DEV_STATE_DIR \
    BUDGETTRACER_SECURE_DATABASE_PATH \
    BUDGETTRACER_DISABLE_APP_LOCK \
    BUDGETTRACER_INITIAL_SECTION \
    BUDGETTRACER_INITIAL_MONTH \
    BUDGETTRACER_INITIAL_CASH_FLOW_BASIS \
    BUDGETTRACER_INITIAL_DATE_RANGE; do
    if [ -n "${!variable:-}" ]; then
      OPEN_ARGS+=(--env "$variable=${!variable}")
    fi
  done

  /usr/bin/open "${OPEN_ARGS[@]}" "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
