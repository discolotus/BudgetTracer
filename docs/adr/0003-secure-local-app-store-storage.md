# ADR 0003: Secure Local App Store Storage

## Status

Accepted

## Context

BudgetTracer is intentionally one local user per install. For App Store use, the app still needs production-grade handling for financial ledger data, Plaid access tokens, and app unlock behavior.

## Decision

- Keep the canonical financial ledger on device.
- Store the ledger in SQLCipher-backed SQLite under the app container's Application Support directory.
- Pin Zetetic's official `SQLCipher.swift` Swift Package binary XCFramework and do not link app targets against system `libsqlite3`.
- Store SQLCipher key material and Plaid access tokens in Keychain with an unlocked-device accessibility class that supports encrypted OS backup restore.
- Use Sign in with Apple only to authenticate calls to a stateless Plaid relay.
- Do not store Plaid access tokens or ledger rows on the relay backend.
- Configure the relay with `BUDGETTRACER_APPLE_AUDIENCE` in production so it validates Sign in with Apple identity tokens against Apple's JWKS.
- Require device-owner authentication before secure-local financial data is shown.
- Keep demo mode as the default development mode; secure-local mode is selected with `BUDGETTRACER_DATA_MODE=secure-local` or `BUDGETTRACER_SECURE_LOCAL=1`.

## Consequences

- Secure-local mode fails closed when the runtime SQLite library does not report SQLCipher support.
- Local sandbox scripts may still use the existing development backend and file token vault, but those are not the App Store storage path.
- Xcode app targets now declare Sign in with Apple, associated domains, Keychain access, and macOS App Sandbox entitlements. The associated domain value must be replaced with the production Plaid OAuth domain before release.
