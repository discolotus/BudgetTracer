# Technical Debt

This file tracks known engineering follow-ups that should not block the current
secure-local production path, but should stay visible before broader release.

## App Attest Relay Enforcement

Status: deferred.

BudgetTracer should eventually add Apple App Attest for the iOS Plaid relay
path. The goal is to prove that requests to `/v1/plaid/*` come from a legitimate
BudgetTracer app instance, not only from someone holding a valid Apple identity
token.

Do not implement this as a cosmetic request header. Real enforcement needs:

- A challenge endpoint for one-time attestation and assertion challenges.
- App-side `DCAppAttestService` key generation, attestation, and assertion
  generation.
- Server-side attestation verification against Apple's App Attest format.
- Server-side storage for attested key IDs, public keys, Apple user subjects,
  and assertion counters, likely using Cloudflare KV or D1.
- A rollout mode such as `APP_ATTEST_MODE=off|report|enforce` so dev and macOS
  flows remain usable while iOS enforcement is tested.

Keep macOS behavior separate. Apple's App Attest API is present in the SDK, but
`DCAppAttestService.isSupported` is false for apps running on Mac devices, so
Sign in with Apple remains the main macOS relay control.
