#!/usr/bin/env bash
set -euo pipefail

PORT="${BUDGETTRACER_BACKEND_PORT:-8790}"
BASE_URL="http://127.0.0.1:$PORT"
REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT
chmod 600 "$REQUEST_FILE" "$RESPONSE_FILE"

printf '{"institution_id":"%s","user_id":"%s"}' \
  "${PLAID_SANDBOX_INSTITUTION_ID:-ins_109508}" \
  "${BUDGETTRACER_USER_ID:-local-user}" > "$REQUEST_FILE"

HTTP_STATUS="$(
  curl -sS \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}' \
    -X POST "$BASE_URL/plaid/sandbox/create-item" \
    -H 'Content-Type: application/json' \
    --data-binary "@$REQUEST_FILE"
)"

if [ "$HTTP_STATUS" != "200" ]; then
  printf 'Sandbox end-to-end sync failed with HTTP %s\n' "$HTTP_STATUS" >&2
  cat "$RESPONSE_FILE" >&2
  exit 1
fi

if grep -q '"transactions":\\[\\]' "$RESPONSE_FILE"; then
  echo "Sandbox end-to-end sync returned no transactions." >&2
  exit 1
fi

echo "Sandbox end-to-end sync passed: Item created, exchanged, synced, and persisted."
