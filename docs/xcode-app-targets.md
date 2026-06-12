# Xcode App Targets

BudgetTracer has a generated Xcode project at:

```text
BudgetTracer.xcodeproj
```

The source of truth is:

```text
project.yml
```

Regenerate the project after changing target structure:

```bash
./script/generate_xcode_project.sh
```

## Targets

- `BudgetTraceriOS`: iOS SwiftUI app target.
- `BudgetTracerMacApp`: macOS SwiftUI app target.

Both targets depend on local Swift package products:

- `BudgetCore`
- `BudgetTracerSharedUI`

The app lifecycle files live outside the package:

```text
Apps/BudgetTraceriOS/App/BudgetTracerIOSApp.swift
Apps/BudgetTracerMac/App/BudgetTracerMacApp.swift
```

## Schemes

- `BudgetTracer iOS`
- `BudgetTracer macOS`

Both schemes set:

```text
BUDGETTRACER_USE_BACKEND=0
BUDGETTRACER_BACKEND_URL=http://127.0.0.1:8790
```

With `BUDGETTRACER_USE_BACKEND=0`, the apps use in-memory sample data and do not touch Plaid, the backend, or Keychain. This is the preferred mode for UI review.

Start the local backend before running either app only when backend mode is enabled:

```bash
./script/run_backend.sh --background
```

Or open Xcode with the backend started:

```bash
./script/open_xcode.sh
```

## Building

When the local Xcode install is healthy:

```bash
./script/build_xcode_apps.sh
```

This builds:

- `BudgetTracer macOS` for macOS
- `BudgetTracer iOS` for generic iOS Simulator

## CI Coverage

The repository includes a GitHub Actions workflow at:

```text
.github/workflows/ci.yml
```

The workflow runs `swift test` and `./script/build_xcode_apps.sh` on macOS for pushes to `main` and pull requests. Publishing is intentionally not automated yet because release signing, provisioning profiles, and App Store Connect credentials are not present in the repository.
