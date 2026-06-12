# ADR 0001: Shared SwiftUI Apple Platform Architecture

## Status

Accepted

## Context

BudgetTracer needs to become both an iOS app and a macOS app. The two clients should evolve together because they will share the same budgeting concepts, financial data provider integration, and summary calculations.

## Decision

Use SwiftUI across iOS and macOS with shared packages for the domain model and reusable UI surfaces. Keep Plaid behind a `FinancialDataProvider` protocol. Keep a runnable SwiftPM macOS shell for local iteration, and maintain generated Xcode iOS and macOS app targets for simulator, device, and release-oriented builds.

## Consequences

- Budget calculations can be tested without UI or Plaid.
- Plaid SDK choices can change without rewriting views.
- iOS and macOS screens can share composition while still allowing platform-specific shell behavior.
- `project.yml` is the source of truth for the generated Xcode project used by simulator, device, signing, entitlements, and App Store packaging work.
