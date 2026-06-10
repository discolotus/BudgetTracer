#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="${BUDGETTRACER_PLAID_SECRETS_PATH:-$HOME/.budgettracer/secrets/PlaidSecrets.imported}"
CLIENT_ID="${PLAID_CLIENT_ID:-}"
SECRET="${PLAID_SANDBOX_SECRET:-${PLAID_SECRET:-}}"
REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

chmod 600 "$REQUEST_FILE" "$RESPONSE_FILE"

read_secret_file_value() {
  local key="$1"
  local file="$2"

  awk -F= -v key="$key" '
    $0 ~ "^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=" {
      value=$0
      sub("^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=[[:space:]]*", "", value)
      sub(/[[:space:]]*$/, "", value)
      if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
          (substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047")) {
        value=substr(value, 2, length(value) - 2)
      }
      print value
      exit
    }
  ' "$file"
}

if [ -z "$CLIENT_ID" ] && [ -f "$SECRETS_FILE" ]; then
  CLIENT_ID="$(read_secret_file_value PLAID_CLIENT_ID "$SECRETS_FILE")"
fi

if [ -z "$SECRET" ] && [ -f "$SECRETS_FILE" ]; then
  SECRET="$(read_secret_file_value PLAID_SANDBOX_SECRET "$SECRETS_FILE")"
fi

if [ -z "$CLIENT_ID" ] || [ -z "$SECRET" ]; then
  if [ "${BUDGETTRACER_PLAID_CREDENTIAL_STORE:-file}" = "keychain" ]; then
    SERVICE_NAME="com.budgettracer.plaid.sandbox"
    CLIENT_ID="$(security find-generic-password -w -a PLAID_CLIENT_ID -s "$SERVICE_NAME")"
    SECRET="$(security find-generic-password -w -a PLAID_SANDBOX_SECRET -s "$SERVICE_NAME")"
  else
    echo "Missing Plaid sandbox credentials. Set PLAID_CLIENT_ID/PLAID_SANDBOX_SECRET or create $SECRETS_FILE." >&2
    echo "To use Keychain instead, set BUDGETTRACER_PLAID_CREDENTIAL_STORE=keychain." >&2
    exit 2
  fi
fi

printf '{"client_id":"%s","secret":"%s","client_name":"BudgetTracer","user":{"client_user_id":"local-smoke-test"},"products":["transactions"],"country_codes":["US"],"language":"en","transactions":{"days_requested":730}}' \
  "$CLIENT_ID" \
  "$SECRET" > "$REQUEST_FILE"

HTTP_STATUS="$(
  curl -sS \
    -o "$RESPONSE_FILE" \
    -w '%{http_code}' \
    -X POST 'https://sandbox.plaid.com/link/token/create' \
    -H 'Content-Type: application/json' \
    --data-binary "@$REQUEST_FILE"
)"

if [ "$HTTP_STATUS" != "200" ]; then
  printf 'Plaid sandbox smoke test failed with HTTP %s\n' "$HTTP_STATUS" >&2
  awk 'BEGIN{RS=","} /error_code|error_message|display_message/ {gsub(/[{}"]/, ""); print}' "$RESPONSE_FILE" >&2
  exit 1
fi

if grep -q '"link_token"' "$RESPONSE_FILE"; then
  echo "Plaid sandbox smoke test passed: link token created."
else
  echo "Plaid sandbox smoke test failed: response did not include link_token." >&2
  exit 1
fi
