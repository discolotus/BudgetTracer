# Cloudflare Worker Plaid Relay

BudgetTracer's first production backend should be a stateless Cloudflare Worker.
It keeps Plaid API credentials out of the Apple apps while leaving the encrypted
ledger and Plaid access tokens on the user's device.

## URLs

Development path:

```text
https://budgettracer-plaid-relay-dev.<your-cloudflare-subdomain>.workers.dev
```

Production paths:

```text
https://budgettracer-plaid-relay.<your-cloudflare-subdomain>.workers.dev
https://api.budgettracer.app
https://app.budgettracer.com/.well-known/apple-app-site-association
https://app.budgettracer.com/plaid/oauth
```

The committed Worker config uses `workers.dev` for `dev` and the default
`production` environment. This is the free production path and does not require a
domain. The `production-owned` environment is ready for Cloudflare Custom
Domains after an owned domain is available. Custom Domains attach a Worker to a
hostname in an active Cloudflare zone and Cloudflare manages the DNS record and
certificate for that hostname. `production-owned` also sets `API_HOSTS` and
`LINK_HOSTS` so `/v1/plaid/*` only answers on `api.budgettracer.app`, while
Universal Link/OAuth paths only answer on `app.budgettracer.com`.

Worker Preview URLs are explicitly disabled in `wrangler.jsonc`. The relay only
needs the stable dev, production `workers.dev`, and future owned-domain URLs;
versioned or aliased preview URLs would create extra public entry points for the
same financial API surface.

## Repo Layout

```text
workers/plaid-relay/
  src/index.js
  wrangler.jsonc
  package.json
  .dev.vars.example
```

Commit Worker code, Wrangler config, route names, public app identifiers, and
required secret names. Do not commit `.dev.vars`, `.env`, Plaid secrets, or
Cloudflare API tokens.

## CI Deployments

The `Cloudflare Worker` GitHub Actions workflow tests the Worker on pull
requests and on pushes to `main`. Deployment uses Cloudflare's official Wrangler
GitHub Action with `wrangler deploy`.

Create a Cloudflare API token with the `Edit Cloudflare Workers` permission and
scope it to the Cloudflare account and owned zones used by BudgetTracer. Store it
in GitHub secrets as `CLOUDFLARE_API_TOKEN`; also store the account ID as
`CLOUDFLARE_ACCOUNT_ID`. Keep both values in GitHub environment secrets, not in
the repo.

The workflow uses three GitHub environments:

```text
cloudflare-dev
cloudflare-production
cloudflare-production-owned
```

Use GitHub environment protection rules on `cloudflare-production` and
`cloudflare-production-owned` if production deploys should require approval.

## Initial Setup

Install dependencies:

```bash
cd workers/plaid-relay
npm install
```

Create a local secret file from the example:

```bash
cp .dev.vars.example .dev.vars
```

Fill in local sandbox values in `.dev.vars`.

Run locally:

```bash
npm run dev
```

Run unit tests:

```bash
npm test
```

## Deploy Dev Worker

Set dev secrets in Cloudflare, either through CI or from a local shell.

For CI, add these GitHub environment secrets to `cloudflare-dev`:

```text
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
PLAID_CLIENT_ID
PLAID_SANDBOX_SECRET
DEV_BEARER_TOKEN
```

The `Cloudflare Worker` GitHub Actions workflow deploys dev only when manually
run with `environment=dev`.

For a local deploy, set the same Worker secrets in Cloudflare:

```bash
cd workers/plaid-relay
npx wrangler secret put PLAID_CLIENT_ID --env dev
npx wrangler secret put PLAID_SANDBOX_SECRET --env dev
npx wrangler secret put DEV_BEARER_TOKEN --env dev
```

Deploy to `workers.dev`:

```bash
npm run deploy:dev
```

After deployment, Wrangler prints the concrete dev URL. Use that URL in the app
with:

```bash
BUDGETTRACER_DATA_MODE=secure-local
BUDGETTRACER_PLAID_RELAY_URL=https://budgettracer-plaid-relay-dev.<your-cloudflare-subdomain>.workers.dev
BUDGETTRACER_APPLE_IDENTITY_TOKEN=<real-or-dev-token>
```

## Deploy Free Production Worker

Before production deploy:

- Replace `TEAMID.com.budgettracer.ios` and `TEAMID.com.budgettracer.mac` in
  `wrangler.jsonc` with real Apple Team ID app IDs.
- Register
  `https://budgettracer-plaid-relay.<your-cloudflare-subdomain>.workers.dev/plaid/oauth`
  in the Plaid Dashboard.
- Confirm the app entitlements include the matching `applinks:` domain if Plaid
  OAuth is required.

Set production secrets in CI or from a local shell.

For CI, add these GitHub environment secrets to `cloudflare-production`:

```text
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
PLAID_CLIENT_ID
PLAID_PRODUCTION_SECRET
```

The `Cloudflare Worker` GitHub Actions workflow deploys production only when
manually run with `environment=production` from the `main` branch.

For a local deploy, set the same Worker secrets in Cloudflare:

```bash
cd workers/plaid-relay
npx wrangler secret put PLAID_CLIENT_ID --env production
npx wrangler secret put PLAID_PRODUCTION_SECRET --env production
```

Deploy:

```bash
npm run deploy:production
```

Smoke check:

```bash
curl https://budgettracer-plaid-relay.<your-cloudflare-subdomain>.workers.dev/health
curl https://budgettracer-plaid-relay.<your-cloudflare-subdomain>.workers.dev/.well-known/apple-app-site-association
```

## Deploy Owned-Domain Production Worker

Use this path after buying or attaching a domain to Cloudflare.

Before owned-domain production deploy:

- Add the owned zones to Cloudflare.
- Replace `TEAMID.com.budgettracer.ios` and `TEAMID.com.budgettracer.mac` in
  `wrangler.jsonc` with real Apple Team ID app IDs.
- Confirm the route domains in `wrangler.jsonc` match the domains you own.
- Register `https://app.budgettracer.com/plaid/oauth` in the Plaid Dashboard.
- Confirm the app entitlements include the matching `applinks:` domain.

Use the same production CI secrets, but add them to the
`cloudflare-production-owned` GitHub environment. The workflow deploys the
owned-domain Worker only when manually run with `environment=production-owned`
from the `main` branch.

For a local deploy, set the same Worker secrets in Cloudflare:

```bash
cd workers/plaid-relay
npx wrangler secret put PLAID_CLIENT_ID --env production-owned
npx wrangler secret put PLAID_PRODUCTION_SECRET --env production-owned
```

Deploy:

```bash
npm run deploy:production-owned
```

Smoke check:

```bash
curl https://api.budgettracer.app/health
curl https://app.budgettracer.com/.well-known/apple-app-site-association
```

## API Endpoints

- `GET /health`
- `GET /.well-known/apple-app-site-association`
- `GET /plaid/oauth`
- `POST /v1/plaid/link-token`
- `POST /v1/plaid/exchange-public-token`
- `POST /v1/plaid/accounts/get`
- `POST /v1/plaid/transactions/sync`
- `POST /v1/plaid/item/remove`

All `/v1/plaid/*` endpoints require an `Authorization: Bearer <token>` header.
Production verifies Sign in with Apple identity tokens against Apple's public
keys and the configured `APPLE_AUDIENCES` list. Configure both bundle IDs when
macOS and iOS use the same relay, for example
`com.budgettracer.ios,com.budgettracer.mac`.

In non-production only, `DEV_BEARER_TOKEN` can be used as a fixed bearer token
for curl and local integration testing.
