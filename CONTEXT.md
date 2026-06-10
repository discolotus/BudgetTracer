# BudgetTracer Context

BudgetTracer is a personal or household budgeting product for iOS and macOS. It should be designed as one product across two Apple platforms rather than as two unrelated clients.

## Product Intent

- Help users understand budgets, balances, spending, and income from connected financial data.
- Integrate with financial data providers, probably Plaid.
- Support multiple representations of financial data as the product model becomes clearer.
- Let users mark recurring monthly income and spending transactions so charts can spread those amounts across the month instead of showing misleading date-specific spikes.

## Engineering Intent

- Shared-first Swift architecture.
- SwiftUI for common UI composition.
- Shared domain package owns money, accounts, transactions, categories, budget summaries, and provider contracts.
- Platform shells stay thin and platform-specific.
- Plaid integration must remain behind a service boundary so tests and UI previews can use local data.
- Normalized monthly cash-flow views should preserve raw transaction history while layering user-owned recurrence selections and derived daily averages on top.
- The financial database should be durable, flat, and query-oriented: a canonical account/transaction ledger that supports normal financial app queries first, with specialized views computed from that ledger rather than baked into the storage model.
- Source code should prefer deeper nested module layouts grouped by responsibility over wide, flat target roots. This is a code-organization preference and does not change the flat/query-oriented database design.
- Xcode app targets live in a generated `BudgetTracer.xcodeproj` from `project.yml`; platform lifecycle code belongs under `Apps/`, while shared domain/UI remains in Swift package products.
- App UI review should default to demo/sample data mode. Plaid and Keychain access must be opt-in through explicit backend/Plaid scripts or `BUDGETTRACER_USE_BACKEND=1`, to avoid repeated macOS password prompts.

## Initial Platform Decision

Use a Swift package for shared `BudgetCore` and `BudgetTracerSharedUI`, plus a SwiftPM macOS executable shell for immediate local iteration. Add normal Xcode iOS and macOS app targets when signing, entitlements, assets, capabilities, and App Store packaging become necessary.
