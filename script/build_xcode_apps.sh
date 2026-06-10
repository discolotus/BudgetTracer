#!/usr/bin/env bash
set -euo pipefail

PROJECT="BudgetTracer.xcodeproj"

xcodebuild \
  -project "$PROJECT" \
  -scheme "BudgetTracer macOS" \
  -destination "platform=macOS" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project "$PROJECT" \
  -scheme "BudgetTracer iOS" \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
