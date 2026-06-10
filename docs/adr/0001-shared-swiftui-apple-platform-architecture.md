# ADR 0001: Shared SwiftUI Apple Platform Architecture

## Status

Accepted

## Context

BudgetTracer needs to become both an iOS app and a macOS app. The two clients should evolve together because they will share the same budgeting concepts, financial data provider integration, and summary calculations.

## Decision

Use SwiftUI across iOS and macOS with shared packages for the domain model and reusable UI surfaces. Keep Plaid behind a `FinancialDataProvider` protocol. Start with a runnable macOS shell for local iteration and add installable Xcode app targets when platform capabilities and signing requirements are introduced.

## Consequences

- Budget calculations can be tested without UI or Plaid.
- Plaid SDK choices can change without rewriting views.
- iOS and macOS screens can share composition while still allowing platform-specific shell behavior.
- A full Xcode project will be needed before simulator/device distribution, signing, entitlements, or App Store packaging.
