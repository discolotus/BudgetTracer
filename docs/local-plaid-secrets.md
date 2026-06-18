# Local Plaid Secrets

BudgetTracer defaults to a no-popup local Plaid setup:

```text
credentials: ~/.budgettracer/secrets/PlaidSecrets.imported
access tokens: ~/.budgettracer/secrets/plaid_access_tokens.json
```

Both files should stay outside the repo. The backend creates the secrets directory with private permissions and writes access tokens with `0600` permissions.

The expected credential file shape is:

```bash
PLAID_CLIENT_ID=...
PLAID_SANDBOX_SECRET=...
# Optional, required for production OAuth institutions on iOS and macOS.
PLAID_REDIRECT_URI=https://your-domain.example/plaid/oauth
```

Production relay deployments should use environment-backed credentials instead
of local files:

```bash
export BUDGETTRACER_PLAID_CREDENTIAL_STORE=environment
export BUDGETTRACER_PLAID_ENVIRONMENT=production
export PLAID_CLIENT_ID=...
export PLAID_PRODUCTION_SECRET=...
```

You can override the credential path:

```bash
export BUDGETTRACER_PLAID_SECRETS_PATH=/path/to/PlaidSecrets
```

You can override the local access-token vault path:

```bash
export BUDGETTRACER_PLAID_TOKEN_VAULT_PATH=/path/to/plaid_access_tokens.json
```

You can also provide the Plaid redirect URI through the backend environment instead of the credential file:

```bash
export PLAID_REDIRECT_URI=https://your-domain.example/plaid/oauth
```

For OAuth flows, this URI must be registered in the Plaid Dashboard. iOS also needs this URI set up as a Universal Link. macOS runs Plaid Link in a `WKWebView`; when Plaid redirects back with `oauth_state_id`, the app intercepts that full URL and reinitializes Link with `receivedRedirectUri`.

## Keychain Opt-In

Keychain support remains available, but it is no longer the default local path because macOS may prompt repeatedly during automated testing. To use Keychain, set:

```bash
export BUDGETTRACER_PLAID_CREDENTIAL_STORE=keychain
export BUDGETTRACER_PLAID_TOKEN_VAULT=keychain
```

Keychain entries use:

```text
service: com.budgettracer.plaid.sandbox
account: PLAID_CLIENT_ID
account: PLAID_SANDBOX_SECRET
```

Do not commit Plaid secrets, paste them into chat, print them in logs, or put them in an Apple app bundle.

To import an env-style file into Keychain:

```bash
./script/import_plaid_secrets_to_keychain.sh /path/to/PlaidSecrets
```

To verify sandbox connectivity without printing secrets or Link tokens:

```bash
./script/plaid_sandbox_smoke.sh
```

To verify the full local backend path after starting the backend:

```bash
./script/run_backend.sh --background
./script/plaid_sandbox_e2e.sh
```

This creates a Sandbox Item through Plaid's Sandbox-only public-token endpoint, exchanges it through the backend, syncs transactions, and persists the result to the local SQLite database.

Normal app UI review should use demo mode instead:

```bash
./script/run_local_stack.sh
```

Demo mode does not read Keychain and does not call Plaid.

## Secure-Local Dev Secret Store

The secure-local app path normally stores the SQLCipher database key and Plaid
access-token refs in Keychain. That is the production behavior, but local
SwiftPM app bundles are rebuilt and ad-hoc signed often enough that macOS may
ask for Keychain access repeatedly.

To opt into a separate local file-backed dev store:

```bash
BUDGETTRACER_DEV_SECRET_STORE=file ./script/build_and_run.sh
```

That stores development-only secret material outside the repo under:

```text
~/.budgettracer/secure-local-dev/secrets
~/.budgettracer/secure-local-dev/BudgetTracer.sqlite
```

To override the location:

```bash
export BUDGETTRACER_DEV_STATE_DIR=/path/to/dev-state
```

To test the production Keychain path locally:

```bash
export BUDGETTRACER_DEV_SECRET_STORE=keychain
```

If `BUDGETTRACER_DEV_SECRET_STORE` is unset, secure-local uses the normal
Keychain-backed app-container database so existing connected accounts remain
visible.

If you keep a plaintext credential file for local sandbox work, it should live outside the repo with `chmod 600` inside a private directory. Use production-grade secret storage before connecting real user data.
