#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/CodexUsageChecks"

swiftc -O -sdk "$(xcrun --show-sdk-path)" \
    "${DIR}/Tests/codex-usage/main.swift" \
    "${DIR}/ClaudeUsageMenuBar/CodexUsage.swift" \
    "${DIR}/ClaudeUsageMenuBar/UsageModels.swift" \
    "${DIR}/ClaudeUsageMenuBar/Account.swift" \
    -o "${OUT}" -module-name CodexUsageChecks
"${OUT}"
