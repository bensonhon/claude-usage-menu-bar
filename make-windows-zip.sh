#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
WINDOWS_DIR="${PROJECT_DIR}/windows"
BUILD_DIR="${PROJECT_DIR}/build"
PUBLISH_DIR="${BUILD_DIR}/windows-publish"

VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "${WINDOWS_DIR}/ClaudeUsageTray/ClaudeUsageTray.csproj")"
ZIP="${BUILD_DIR}/ClaudeUsageTray-v${VERSION}-windows-x64.zip"

echo "==> Running Windows core tests..."
dotnet test "${WINDOWS_DIR}/ClaudeUsageTray.Tests" --nologo

echo "==> Publishing ClaudeUsageTray v${VERSION} for win-x64..."
rm -rf "${PUBLISH_DIR}"
dotnet publish "${WINDOWS_DIR}/ClaudeUsageTray" -c Release -o "${PUBLISH_DIR}" --nologo

echo "==> Packaging ${ZIP}..."
rm -f "${ZIP}"
(cd "${PUBLISH_DIR}" && zip -q -X "${ZIP}" ClaudeUsageTray.exe)
rm -rf "${PUBLISH_DIR}"

echo ""
echo "==> Windows zip ready: ${ZIP}"
