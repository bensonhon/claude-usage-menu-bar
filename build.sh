#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageMenuBar"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

SDK="$(xcrun --show-sdk-path)"

echo "==> Building ${APP_NAME}..."

# Clean previous build
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Compile
swiftc -parse-as-library -O \
    -target arm64-apple-macosx14.0 \
    -sdk "${SDK}" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageService.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageModels.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/MenuBarIconView.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsagePopoverView.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageRingView.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/TokenHistoryView.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/RecentSessionsView.swift" \
    "${PROJECT_DIR}/ClaudeUsageMenuBar/Settings.swift" \
    -o "${MACOS_DIR}/${APP_NAME}"

# Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsageMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.benson.claude-usage-menu-bar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Claude Usage Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.1</string>
    <key>CFBundleVersion</key>
    <string>1.3.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Copy app icon
if [ -f "${PROJECT_DIR}/ClaudeUsageMenuBar/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/ClaudeUsageMenuBar/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Ad-hoc sign
codesign --force --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "==> Build succeeded!"
echo "    App: ${APP_BUNDLE}"

# Install
if [ "${1:-}" = "--install" ]; then
    if [ -d "/Applications/${APP_NAME}.app" ]; then
        echo "    Removing existing installation..."
        rm -rf "/Applications/${APP_NAME}.app"
    fi
    cp -R "${APP_BUNDLE}" /Applications/
    echo "    Installed to /Applications/${APP_NAME}.app"
fi

# Launch
if [ "${1:-}" = "--launch" ] || [ "${2:-}" = "--launch" ]; then
    open "${APP_BUNDLE}"
fi
