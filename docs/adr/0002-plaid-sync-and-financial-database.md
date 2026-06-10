# ADR 0002: Plaid Sync and Financial Database

## Status

Accepted

## Context

BudgetTracer needs Plaid-backed accounts and transactions while preserving user-owned budget behavior such as category overrides, notes, and regular-monthly transaction selections. Plaid credentials must not live in the iOS or macOS app.

Plaid's recommended Transactions model is `/transactions/sync`: store a cursor per Item, patch `added`, `modified`, and `removed` updates into the local database, and listen for `SYNC_UPDATES_AVAILABLE` webhooks. Link creates a temporary `public_token`, which the backend exchanges for an `access_token`.

## Decision

Use a backend-owned Plaid integration and a durable, flat, query-oriented relational database.

- Apple clients receive Link tokens from the backend and send public tokens back to the backend after Link succeeds.
- The backend exchanges public tokens for Plaid access tokens.
- The database stores an `access_token_ref`, not raw access tokens.
- A token vault stores the actual Plaid access token; local sandbox development defaults to a private file vault to avoid macOS prompt loops, and production should use a managed secrets system or encrypted vault.
- The database stores Plaid Items, accounts, transactions, sync cursors, webhook events, and sync events.
- User-owned annotations are separate from raw Plaid transactions.
- Removed Plaid transactions are soft-removed with `removed_at` so sync history and user annotations are not destructively erased.
- `/transactions/sync` is paginated until `has_more` is false; the Item cursor advances only after all pages in a sync attempt are applied.
- Sync attempts write `sync_events` rows with success/failure status and item-level change counts.
- Webhook receipt IDs are derived from the raw webhook payload hash so Plaid retries can be handled idempotently.
- The database is the canonical financial ledger and must support normal financial app query patterns directly: account balances over time, spending by merchant/category/account, income vs expense, cash-flow windows, pending vs posted reconciliation, institution/account filters, search, exports, audits, and user budget annotations.
- The normalized monthly view is a derived projection over raw transactions plus `transaction_annotations`; it must not distort or replace the canonical transaction ledger.

## Schema Shape

- `users`: application user identities.
- `institutions`: financial institutions linked by users.
- `plaid_items`: Plaid Item identity, institution link, `access_token_ref`, sync cursor, status, and reauth state.
- `accounts`: normalized account balances keyed by Plaid account ID.
- `transactions`: normalized transaction ledger keyed by Plaid transaction ID.
- `transaction_annotations`: user-owned category, regular-monthly flag, and note.
- `budget_categories`: user-owned budget categories.
- `plaid_webhook_events`: raw webhook receipt log for idempotent processing.
- `sync_events`: operational sync history.

## Query Design

The schema should stay flat enough that common app screens and reports can query the ledger without reconstructing nested API payloads. Plaid response structure is an ingestion concern, not the storage shape.

The primary query paths are:

- transactions by user, account, and date range
- account balances and latest account state by user and institution
- spending and income grouped by category, merchant, account, and month
- pending transaction replacement and removed-transaction audit history
- budget annotations and recurring-monthly selections joined onto transactions
- Plaid sync state by Item, including cursor, status, reauth flag, and webhook history

Derived views, including normalized monthly cash-flow projections, should be built from these flat tables and may be cached later only as invalidatable projections.

## Amount Convention

Plaid transaction amounts are positive for money leaving the account and negative for money entering the account. BudgetTracer stores the opposite convention in `Money`: income is positive and spending is negative. The Plaid sync service converts signs at the boundary.

## Consequences

- The app can render cached budget state without querying Plaid on every launch.
- Plaid sync can be retried safely using cursors.
- Budget annotations survive Plaid transaction modifications and soft removals.
- Credentials stay out of the Apple app and out of ordinary transaction tables.
- Production still needs a real backend runtime, authenticated client API, webhook endpoint, and production token vault before real user data is connected.
- Local development has a loopback backend and Sandbox-only Item creation route for end-to-end testing without embedding Plaid credentials in the Apple app.
- Keychain remains available locally by setting `BUDGETTRACER_PLAID_CREDENTIAL_STORE=keychain` and `BUDGETTRACER_PLAID_TOKEN_VAULT=keychain`, but it is not the default because automated CLI workflows can trigger repeated macOS prompts.
