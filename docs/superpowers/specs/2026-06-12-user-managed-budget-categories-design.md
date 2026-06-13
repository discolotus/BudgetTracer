# User-Managed Budget Categories — Design

Date: 2026-06-12
Scope: BudgetCore, BudgetPersistence, BudgetTracerBackend, BudgetTracerSharedUI.

## Goal

Let users create, rename, set/clear a monthly limit on, and delete budget categories from
the Budgets tab. Seed a small default set for a new/empty user so the budget picker and tab
are never empty.

## Default set

Income, Housing, Groceries, Other. No preset limits. Seeded only when a user has zero
categories (backend `ensureUser`). The demo fixture (`SampleBudgetData`) already ships its
own richer set and is left unchanged.

## Stack

### Persistence
- `deleteBudgetCategory(id:userID:)` — delete row; `transaction_annotations.category_id`
  FK is `ON DELETE SET NULL`, so affected transactions become Uncategorized automatically.
- `seedDefaultCategoriesIfEmpty(userID:)` — inserts the default 4 with stable ids
  (`default-income`, …) only if the user has no categories. Called from `ensureUser`.
- (`upsertBudgetCategory` already added.)

### Core provider
- `FinancialDataProvider.saveCategory(_:) -> BudgetSnapshot` (upsert by id).
- `FinancialDataProvider.deleteCategory(id:) -> BudgetSnapshot`.
- Default in-memory impls mutate the fetched snapshot (upsert into `categories`; delete +
  clear matching `transaction.categoryID`).

### Backend
- `PUT /categories` (upsert) and `DELETE /categories` (id in body) → repository → snapshot.
- DTOs `UpsertCategoryRequest { id?, name, monthly_limit_minor_units?, user_id? }`,
  `DeleteCategoryRequest { id, user_id? }`.
- `BackendFinancialDataProvider` issues both.

### Workspace
- `addCategory(name:monthlyLimit:)` mints a UUID id, calls `saveCategory`.
- `updateCategory(_:)` (rename / limit) → `saveCategory`.
- `deleteCategory(id:)` → `deleteCategory`.
- Optimistic local snapshot mutation, same pattern as `setCategory`.

### UI — Budgets tab
- Header gains an "Add" button → `CategoryEditorSheet` (name + optional monthly limit).
- Each row is tappable → same sheet in edit mode (rename, limit, Delete).
- `CategoryEditorSheet` is shared (iOS/macOS), styled with the design tokens.
- Spend bar/labels unchanged.

## Validation

- Empty/whitespace name disabled in the editor.
- Monthly limit optional; entered in dollars, stored as minor units.
- Delete asks for confirmation (`confirmationDialog`).

## Out of scope

- Reordering categories, category colors/icons, nested categories.

## Testing

- Repo: `seedDefaultCategoriesIfEmpty` seeds 4 once and is idempotent; `deleteBudgetCategory`
  nulls annotations.
- Demo provider: save (add + rename) and delete round-trip in the held snapshot.
- `swift build` + `swift test` + iOS xcodebuild; visual check in the macOS shell.
