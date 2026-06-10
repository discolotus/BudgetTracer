#!/usr/bin/env bash
set -euo pipefail

PORT="${BUDGETTRACER_BACKEND_PORT:-8790}"
BASE_URL="http://127.0.0.1:$PORT"

curl -fsS "$BASE_URL/health" >/dev/null
curl -fsS "$BASE_URL/snapshot" >/dev/null

REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
cleanup() {
  rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT
chmod 600 "$REQUEST_FILE" "$RESPONSE_FILE"

printf '{"user_id":"local-smoke-test"}' > "$REQUEST_FILE"
HTTP_STATUS="$(
  curl -sS \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}' \
    -X POST "$BASE_URL/plaid/link-token" \
    -H 'Content-Type: application/json' \
    --data-binary "@$REQUEST_FILE"
)"

if [ "$HTTP_STATUS" != "200" ]; then
  printf 'Backend Plaid Link token smoke failed with HTTP %s\n' "$HTTP_STATUS" >&2
  cat "$RESPONSE_FILE" >&2
  exit 1
fi

if ! grep -q '"link_token"' "$RESPONSE_FILE"; then
  echo "Backend Plaid Link token smoke failed: missing link_token" >&2
  exit 1
fi

echo "Backend smoke passed: health, snapshot, and Plaid Link token routes work."
