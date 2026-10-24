#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/AccountTabsChecks"

swiftc -O -sdk "$(xcrun --show-sdk-path)" \
    "${DIR}/Tests/account-tabs/main.swift" \
    "${DIR}/ClaudeUsageMenuBar/AccountTabsView.swift" \
    "${DIR}/ClaudeUsageMenuBar/UsageRingView.swift" \
    -o "${OUT}" -module-name AccountTabsChecks
"${OUT}"
