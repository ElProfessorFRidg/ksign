#!/bin/bash
set -euo pipefail
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT

# Compile the actual networking service under its package's Swift 6 language mode.
xcrun swiftc -swift-version 6 -parse-as-library -emit-module -module-name NimbleJSON \
  NimbleKit/Sources/NimbleJSON/NBFetchService.swift \
  -o "$CHECK_DIR/NimbleJSON.swiftmodule"

# Exercise repository decoding and networking together on the macOS runner.
xcrun swiftc -swift-version 5 -parse-as-library \
  AltSourceKit/Sources/AltSourceKit/Models/ASRepository.swift \
  NimbleKit/Sources/NimbleJSON/NBFetchService.swift \
  scripts/SourceLoadingChecks.swift \
  -o "$CHECK_DIR/source-checks"
"$CHECK_DIR/source-checks"

