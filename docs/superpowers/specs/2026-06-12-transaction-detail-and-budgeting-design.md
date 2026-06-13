# Transaction Detail & Budget Assignment — Design

Date: 2026-06-12
Scope: BudgetCore, BudgetPersistence, BudgetTracerBackend, BudgetTracerSharedUI.

## Problems

1. **Search can't find by category.** `TransactionSearch.matches` searches merchant + amount
   + date only. Searching "Utilities" (a category) returns nothing, so the recurring list
   looks empty. (The sample data already marks the utilities bill recurring — it was just
   undiscoverable.)
2. **No way to open a transaction.** Rows are static. User wants to tap a transaction and,
   in a popup, mark it regular-monthly and reassign it to a different budget/category.
3. **No category-assignment capability exists** anywhere (provider, workspace, backend),
   even though `transaction_annotations.category_id` already exists in the schema and is
   read back by `fetchSnapshot`.
4. **Demo multi-toggle state loss.** The default `setRegularMonthly` re-fetches the static
   fixture, so toggling a second transaction reverts the first.

## Design

### Category assignment (full stack, vertical slice)

- **Persistence** — `BudgetRepository.setCategory(transactionID:categoryID:userID:)`:
  upsert into `transaction_annotations`, `category_id = excluded.category_id`. `nil`
  clears (uncategorized). Mirrors `setRegularMonthly`.
- **Backend** — `PATCH /transactions/category`; DTO `UpdateCategoryRequest`
  (`transaction_id`, `category_id?`, `user_id?`) → repository → cached snapshot.
- **Core protocol** — `FinancialDataProvider.setCategory(transactionID:categoryID:)`
  with a default that mutates the matching transaction's `categoryID` in the returned
  snapshot.
- **Backend client** — `BackendFinancialDataProvider.setCategory` issues the PATCH.
- **Workspace** — `setCategory(_:categoryID:)`: optimistic local update + provider call,
  same shape as `setTransaction(_:isRecurring:)`.

### Demo provider becomes stateful

Convert `SampleFinancialDataProvider` from a struct to an `actor` seeded with
`SampleBudgetData.snapshot`. `setRegularMonthly` / `setCategory` mutate the held snapshot
and `fetchBudgetSnapshot` returns it, so annotations accumulate across edits in demo mode.

### Search includes category

`TransactionSearch.matches(_:query:categoryName:)` gains an optional category name folded
into the searchable text. Call sites resolve the name from `snapshot.categories`.

### Transaction detail sheet

New `TransactionDetailSheet` (shared): merchant, date, account, signed amount, optional
note; a "Regular monthly" toggle; a category Picker (all categories + "Uncategorized").
Edits call back to workspace setters; the sheet reads live state from the snapshot.

Presentation: `.sheet` on both platforms (medium/large detents on iOS; fixed ~420pt width
on macOS). Reachable from:
- **Transactions tab** — tap any row. Searches all-time (fixes discovery).
- **Balances → Regular Monthly Transactions** — tap a row opens the same sheet; the inline
  toggle stays for quick in-window changes. Its search now includes category.

### Wiring

`BudgetTracerRootView` passes `categories`, `setRecurring`, and `setCategory` into
`TransactionsView` and `NormalizedMonthView`. Both own a `@State selectedTransactionID`
that drives the sheet.

## Out of scope

- Creating/editing categories or budget limits (assignment only).
- Split transactions, bulk edit.

## Testing

- Repository: `setCategory` persists and round-trips through `fetchSnapshot`.
- Search: matches by category name.
- Demo provider: two sequential recurring toggles both stick.
- `swift build` + `swift test`; visual check in the macOS shell.
