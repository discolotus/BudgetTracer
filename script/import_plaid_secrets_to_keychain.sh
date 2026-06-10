#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="${1:-$HOME/.budgettracer/secrets/PlaidSecrets.imported}"
SERVICE_NAME="com.budgettracer.plaid.sandbox"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "Secrets file not found: $SECRETS_FILE" >&2
  exit 1
fi

set -a
source "$SECRETS_FILE"
set +a

: "${PLAID_CLIENT_ID:?missing PLAID_CLIENT_ID}"
: "${PLAID_SANDBOX_SECRET:?missing PLAID_SANDBOX_SECRET}"

security add-generic-password -a PLAID_CLIENT_ID -s "$SERVICE_NAME" -w "$PLAID_CLIENT_ID" -U >/dev/null
security add-generic-password -a PLAID_SANDBOX_SECRET -s "$SERVICE_NAME" -w "$PLAID_SANDBOX_SECRET" -U >/dev/null

echo "Imported Plaid sandbox credentials into macOS Keychain service $SERVICE_NAME"
