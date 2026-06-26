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

# Deployment target shared by every architecture slice. arm64 macOS exists
# only from 11.0 onward, so 13.0 is a valid floor for both slices.
DEPLOYMENT_TARGET="13.0"

# Architectures compiled into the universal binary. Building both arm64 and
# x86_64 lets the app run NATIVELY on Apple Silicon (no Rosetta, so it works on
# macOS 26+ where Rosetta is no longer installed by default) while still
# running natively on any remaining Intel Macs.
ARCHS=(arm64 x86_64)

SOURCES=(
    "${PROJECT_DIR}/ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageService.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageModels.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/MenuBarIconView.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsagePopoverView.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/UsageRingView.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/TokenHistoryView.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/RecentSessionsView.swift"
    "${PROJECT_DIR}/ClaudeUsageMenuBar/Settings.swift"
)

echo "==> Building ${APP_NAME} (universal: ${ARCHS[*]})..."

# Clean previous build
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# swiftc emits a single-architecture binary per invocation, so compile each
# slice separately, then fuse them into one universal binary with lipo.
SLICES=()
for ARCH in "${ARCHS[@]}"; do
    SLICE="${BUILD_DIR}/${APP_NAME}-${ARCH}"
    echo "    Compiling ${ARCH} slice..."
    swiftc -parse-as-library -O \
        -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
        -sdk "${SDK}" \
        "${SOURCES[@]}" \
        -o "${SLICE}"
    SLICES+=("${SLICE}")
done

echo "    Fusing slices into universal binary..."
lipo -create "${SLICES[@]}" -output "${MACOS_DIR}/${APP_NAME}"
rm -f "${SLICES[@]}"

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
    <string>1.3.4</string>
    <key>CFBundleVersion</key>
    <string>1.3.4</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
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
echo "    Architectures: $(lipo -archs "${MACOS_DIR}/${APP_NAME}")"

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
