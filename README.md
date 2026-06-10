# BudgetTracer

BudgetTracer is a paired iOS and macOS budgeting app. The app will connect to financial data, likely through Plaid, and present household budget state through multiple views as those product details become clearer.

## Architecture Direction

- Use SwiftUI for both platforms.
- Keep budgeting models, calculations, and financial sync boundaries in shared Swift packages.
- Keep platform app shells thin: macOS should add desktop affordances such as sidebars, commands, settings, and keyboard shortcuts; iOS should use the same shared views and domain layer with platform-appropriate navigation.
- Treat Plaid as an adapter behind `FinancialDataProvider`, not as a dependency imported directly by views.

## Current Scaffold

- `BudgetCore`: shared money, account, transaction, category, summary, and Plaid-boundary models.
- `BudgetTracerSharedUI`: shared SwiftUI budget screens.
- `BudgetTracerMac`: runnable macOS SwiftUI shell backed by the shared packages.
- `BudgetTracer.xcodeproj`: generated Xcode project with iOS and macOS app targets.

The Xcode app targets depend on `BudgetCore` and `BudgetTracerSharedUI`; their platform lifecycle files live under `Apps/`.

Source targets use nested responsibility folders rather than wide target roots. The intended distinction is: code layout should be deep and navigable; database tables should remain flat and query-oriented.

## Normalized Monthly View

BudgetTracer lets the user mark specific income or spending transactions as regular monthly transactions. The raw transactions remain unchanged, but selected regular items are averaged across every day of the month for plotted cash-flow and balance views. This makes a paycheck, rent payment, utility bill, or other predictable monthly item appear as daily budget pressure instead of a one-day spike.

## Local Development

Build and run the macOS shell in demo mode, with no Plaid or Keychain access:

```bash
./script/run_local_stack.sh
```

Run the local Plaid backend explicitly:

```bash
./script/run_backend.sh --background
```

By default, local Plaid mode reads sandbox credentials from:

```text
~/.budgettracer/secrets/PlaidSecrets.imported
```

and stores sandbox access tokens in:

```text
~/.budgettracer/secrets/plaid_access_tokens.json
```

This avoids macOS Keychain prompts during local testing. Set `BUDGETTRACER_PLAID_CREDENTIAL_STORE=keychain` and `BUDGETTRACER_PLAID_TOKEN_VAULT=keychain` only when intentionally testing the Keychain path.

Run tests:

```bash
swift test
```

## Plaid Integration

The Plaid implementation is split into:

- `BudgetPlaid`: Link token creation, public-token exchange, `/transactions/sync`, and Plaid-to-domain mapping.
- `BudgetPersistence`: SQLite schema, migrations, transaction/account persistence, sync cursors, and user annotations.
- `BudgetCore`: shared app models and the `FinancialDataProvider` boundary.

Plaid access tokens are represented in the database by `access_token_ref`; raw tokens belong in a backend token vault, not in the Apple clients or ordinary data tables. The local sandbox vault is file-backed for predictable no-popup development; Keychain remains available as an explicit opt-in.

The financial database is intended to be the durable canonical ledger for ordinary financial app queries: date-range transactions, account filters, category and merchant rollups, income vs spending, pending/posted reconciliation, exports, and audit history. The normalized monthly view is a derived projection over that ledger plus user annotations, not a special-purpose replacement for the ledger.

## Local Backend

The local backend listens on `http://127.0.0.1:8790` by default and stores its SQLite database at:

```text
~/.budgettracer/BudgetTracer.sqlite
```

Useful scripts:

```bash
./script/backend_smoke.sh
./script/plaid_sandbox_smoke.sh
./script/plaid_sandbox_e2e.sh
./script/run_plaid_stack.sh
./script/run_backend.sh --stop
```

Xcode app target scripts:

```bash
./script/generate_xcode_project.sh
./script/open_xcode.sh
./script/build_xcode_apps.sh
```

The Xcode schemes default to demo mode:

```text
BUDGETTRACER_USE_BACKEND=0
```

Set `BUDGETTRACER_USE_BACKEND=1` only when intentionally testing the Plaid-backed local backend.

Implemented routes:

- `GET /health`
- `GET /snapshot`
- `POST /plaid/link-token`
- `POST /plaid/exchange-public-token`
- `POST /plaid/sandbox/create-item`
- `POST /plaid/sync`
- `POST /plaid/webhook`
- `PATCH /transactions/regular-monthly`
