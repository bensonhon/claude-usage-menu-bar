#!/bin/bash
# ============================================================================
# Claude Usage Menu Bar — One-Click Installer
# ============================================================================
# Double-click this file to install. It will:
#   1. Check prerequisites (Swift, Command Line Tools)
#   2. Fix a known Apple CLT bug if needed
#   3. Compile the app from source
#   4. Install to /Applications
#   5. Launch the app
# ============================================================================

set -euo pipefail

APP_NAME="ClaudeUsageMenuBar"
REPO_URL="https://github.com/bensonhon/claude-usage-menu-bar.git"
TMP_DIR=$(mktemp -d)
INSTALL_DIR="/Applications"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Claude Usage Menu Bar — Installer          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────────

echo -e "${BLUE}[1/5]${NC} Checking prerequisites..."

# Check for Command Line Tools / Swift
if ! command -v swiftc &>/dev/null; then
    echo -e "${YELLOW}Swift compiler not found. Installing Command Line Tools...${NC}"
    xcode-select --install 2>/dev/null || true
    echo ""
    echo -e "${YELLOW}Please wait for Command Line Tools to finish installing,${NC}"
    echo -e "${YELLOW}then double-click this file again.${NC}"
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

echo -e "  ✓ Swift compiler found: $(swiftc --version 2>&1 | head -1)"

# Check for git
if ! command -v git &>/dev/null; then
    echo -e "${RED}git not found. Please install Command Line Tools:${NC}"
    echo "  xcode-select --install"
    read -p "Press Enter to exit..."
    exit 1
fi

# Check Claude Code is logged in
if ! security find-generic-password -s "Claude Code-credentials" -w &>/dev/null; then
    echo -e "${YELLOW}⚠ Claude Code credentials not found in Keychain.${NC}"
    echo -e "${YELLOW}  The app will show data once you log in to Claude Code.${NC}"
    echo ""
fi

# ── Step 2: Fix CLT modulemap bug ───────────────────────────────────────────

echo -e "${BLUE}[2/5]${NC} Checking for known CLT module bug..."

MODULE_MAP="/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap"
if [ -f "$MODULE_MAP" ]; then
    echo -e "  ${YELLOW}Found duplicate SwiftBridging module (known Apple bug).${NC}"
    echo -e "  ${YELLOW}Need sudo to rename it. You may be prompted for your password.${NC}"
    echo ""
    sudo mv "$MODULE_MAP" "${MODULE_MAP}.bak"
    echo -e "  ✓ Fixed module.modulemap"
else
    echo -e "  ✓ No fix needed"
fi

# ── Step 3: Download source ─────────────────────────────────────────────────

echo -e "${BLUE}[3/5]${NC} Downloading source code..."

cd "$TMP_DIR"
git clone --depth 1 "$REPO_URL" source 2>&1 | tail -1
cd source

echo -e "  ✓ Source downloaded"

# ── Step 4: Compile ─────────────────────────────────────────────────────────

echo -e "${BLUE}[4/5]${NC} Compiling (this may take a minute)..."

SDK="$(xcrun --show-sdk-path)"
APP_BUNDLE="${TMP_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc -parse-as-library -O \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "${SDK}" \
    ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift \
    ClaudeUsageMenuBar/UsageService.swift \
    ClaudeUsageMenuBar/UsageModels.swift \
    ClaudeUsageMenuBar/MenuBarIconView.swift \
    ClaudeUsageMenuBar/UsagePopoverView.swift \
    ClaudeUsageMenuBar/UsageRingView.swift \
    ClaudeUsageMenuBar/TokenHistoryView.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

# Create Info.plist
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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo -e "  ✓ Compiled successfully"

# ── Step 5: Install & Launch ─────────────────────────────────────────────────

echo -e "${BLUE}[5/5]${NC} Installing to /Applications..."

# Remove old version if exists
if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    echo -e "  ✓ Removed previous version"
fi

cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/"

# Cleanup
rm -rf "$TMP_DIR"

echo -e "  ✓ Installed to /Applications/${APP_NAME}.app"
echo ""

# Launch
echo -e "${GREEN}${BOLD}✓ Installation complete!${NC}"
echo ""
echo -e "  The app is now running in your menu bar."
echo -e "  Look for the Claude ✦ icon near the clock."
echo ""
echo -e "  ${BOLD}Tips:${NC}"
echo -e "  • Click the icon to see detailed usage"
echo -e "  • Data refreshes every 60 seconds"
echo -e "  • Make sure you're logged in to Claude Code"
echo ""

open "${INSTALL_DIR}/${APP_NAME}.app"

echo -e "  ${BOLD}To uninstall:${NC} Delete /Applications/${APP_NAME}.app"
echo ""
read -p "Press Enter to close this window..."
