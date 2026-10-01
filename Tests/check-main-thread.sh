#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)/MainThreadCheck"

swiftc -O -sdk "$(xcrun --show-sdk-path)" \
    "${DIR}/Tests/main.swift" \
    "${DIR}/ClaudeUsageMenuBar/UsageService.swift" \
    "${DIR}/ClaudeUsageMenuBar/UsageModels.swift" \
    -o "${OUT}" -module-name MainThreadCheck
"${OUT}"
