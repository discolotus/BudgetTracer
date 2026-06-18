# Backend Deployment

BudgetTracer should ship first as a secure-local app plus a minimal Plaid relay.
The app owns the encrypted ledger and Plaid access-token Keychain entries. The
relay owns only Plaid API credentials and forwards authenticated Plaid requests.

## Recommended First Production Shape

Use the Cloudflare Worker in `workers/plaid-relay` as a small HTTPS service.
The no-domain production URL is:

```text
https://budgettracer-plaid-relay.tanner-m-leo.workers.dev
```

The later owned-domain URL is:

```text
https://api.budgettracer.app
```

The service exposes:

- `GET /health`
- `POST /v1/plaid/link-token`
- `POST /v1/plaid/exchange-public-token`
- `POST /v1/plaid/accounts/get`
- `POST /v1/plaid/transactions/sync`
- `POST /v1/plaid/item/remove`

Run it in relay-only mode so development routes such as `/snapshot`,
`/plaid/sandbox/create-item`, category mutation routes, and local sync routes are
not exposed publicly.

The current Swift backend remains useful as the local/dev reference
implementation. The Worker is the preferred free production path.

## Cloudflare Worker Environment

Use `docs/cloudflare-worker.md` as the source of truth for Worker setup. In
short, keep non-secret Worker vars in `workers/plaid-relay/wrangler.jsonc` and
store the real Plaid credentials as Cloudflare secrets:

```bash
wrangler secret put PLAID_CLIENT_ID --env production
wrangler secret put PLAID_PRODUCTION_SECRET --env production
```

The default production Worker can expose the free `workers.dev` URL first:

```text
https://budgettracer-plaid-relay.<your-cloudflare-subdomain>.workers.dev
```

After an owned domain is available, deploy the `production-owned` Worker
environment to expose the owned API URL at `https://api.budgettracer.app` and
the Universal Link/OAuth URL at `https://app.budgettracer.com`.

Do not configure Plaid webhooks for the minimal stateless relay yet. The app
stores access tokens and sync cursors locally, so there is no server-side token
vault for the relay to use when Plaid posts `SYNC_UPDATES_AVAILABLE`. Add
webhooks when moving to a full backend-owned token vault.

## Swift Relay Environment

If we deploy the Swift backend instead of the Worker, run it in relay-only mode:

```bash
BUDGETTRACER_BACKEND_ROUTE_MODE=relay-only
BUDGETTRACER_BACKEND_HOST=0.0.0.0
BUDGETTRACER_BACKEND_PORT=8790

BUDGETTRACER_PLAID_CREDENTIAL_STORE=environment
BUDGETTRACER_PLAID_ENVIRONMENT=production
PLAID_CLIENT_ID=...
PLAID_PRODUCTION_SECRET=...

BUDGETTRACER_APPLE_AUDIENCE=com.budgettracer.ios
PLAID_REDIRECT_URI=https://app.budgettracer.com/plaid/oauth
```

`BUDGETTRACER_APPLE_AUDIENCE` must match the app identifier or service identifier
used by Sign in with Apple. In relay-only mode the backend refuses to start
without it.

## App Configuration

The checked-in app Info.plists default production archives to:

```text
BudgetTracerDataMode=secure-local
BudgetTracerPlaidRelayURL=https://budgettracer-plaid-relay.tanner-m-leo.workers.dev
```

Local Xcode schemes set `BUDGETTRACER_DATA_MODE=demo`, which overrides the
Info.plist and keeps UI review on sample data unless secure-local mode is
explicitly requested.

When the owned-domain Worker is ready, update `BudgetTracerPlaidRelayURL` to
`https://api.budgettracer.app` in the app Info.plists and `project.yml`.

## Backend Options

### Option A: Cloudflare Worker Relay

Use the committed `workers/plaid-relay` project. Development deploys to
`workers.dev`; production can also start on `workers.dev` without buying a
domain. When the app is ready for a branded production URL, deploy
`production-owned` and attach Cloudflare Custom Domains: `api.budgettracer.app`
for API traffic and `app.budgettracer.com` for Universal Link/OAuth paths.

Advantages:

- Starts on Cloudflare's free Worker tier.
- Managed HTTPS and custom-domain certificates.
- No always-on server to operate.
- Fits the stateless relay shape.

Tradeoffs:

- The relay implementation is JavaScript rather than the Swift local reference.
- We need contract tests to keep app and Worker request/response shapes aligned.

### Option B: Swift Relay Behind HTTPS

Use the existing `BudgetTracerBackend` executable in relay-only mode behind Fly,
Render, AWS App Runner, Cloud Run, or a similar platform that terminates TLS and
injects secrets.

Advantages:

- Reuses the Swift Plaid DTOs and request code.
- Keeps relay behavior testable in this repo.
- Fastest path from current code.

Tradeoffs:

- The custom socket server is intentionally simple.
- Production hosting must provide TLS, process supervision, logs, and secret
  management.

### Option C: Full Backend Later

Move Plaid access tokens, sync cursors, webhooks, and ledger storage server-side.

Advantages:

- Enables background sync, multi-device restore, server-side webhooks, and better
  operational observability.

Tradeoffs:

- Larger security, privacy, account, and data-retention surface.
- More backend product work before App Store launch.

The current recommendation is Option A for the first production pass, then
revisit Option C only if multi-device or background sync becomes a near-term
requirement.
