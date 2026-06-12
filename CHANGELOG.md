# Changelog

All notable changes to BudgetTracer are documented here.

## [1.1.0] - 2026-06-10

### Added

- iOS app shell and shared UI parity with the macOS budgeting views.
- macOS app shell parity for the shared Balances, account classification, settings, and refresh surfaces.
- iOS Balances page with 1M, 3M, 6M, 9M, and 1Y date ranges.
- Balances chart modes for account-balance baselines and from-zero normalization.
- Previous-period comparison traces for balance and spending charts where comparison data exists.
- Account classification controls for cash, savings, investment, card, and excluded accounts.
- GitHub Actions CI for Swift tests and macOS/iOS Xcode builds.
- README screenshots for the current iOS and macOS app surfaces.

### Changed

- Cash summaries and balance projections use checking cash by default and exclude investments/funds.
- Chart axes use simpler labels and tighter data ranges for balance readability.
- App versions are now `1.1.0` with build number `2`.
- The local macOS run script forwards Balances launch parameters for section, month, baseline, and range.

### Fixed

- Longer Balances date ranges now clamp to available transaction history so sparse datasets do not compress traces into a small part of the chart.
- Cash and card transaction markers are plotted only on days that have matching transaction activity.
- Money market accounts are mapped as investments by Plaid sync and excluded from checking cash by default.
