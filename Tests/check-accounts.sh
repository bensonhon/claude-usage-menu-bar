#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/AccountChecks"

swiftc -O -sdk "$(xcrun --show-sdk-path)" \
    "${DIR}/Tests/accounts/main.swift" \
    "${DIR}/ClaudeUsageMenuBar/ClaudeAccount.swift" \
    "${DIR}/ClaudeUsageMenuBar/AccountStore.swift" \
    "${DIR}/ClaudeUsageMenuBar/MenuBarIconRenderer.swift" \
    "${DIR}/ClaudeUsageMenuBar/Settings.swift" \
    -o "${OUT}" -module-name AccountChecks
"${OUT}"
