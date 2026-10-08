#!/bin/bash
set -euo pipefail

# Builds the app with build.sh and packages it into a release DMG:
#   build/ClaudeUsageMenuBar-vX.Y.Z.dmg
# The DMG holds the app plus an Applications shortcut so users can drag it
# straight across.

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageMenuBar"
VOLUME_NAME="Claude Usage Monitor"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

"${PROJECT_DIR}/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_BUNDLE}/Contents/Info.plist")"
DMG="${BUILD_DIR}/${APP_NAME}-v${VERSION}.dmg"

# build.sh ignores codesign errors; refuse to package a bundle whose signature
# is missing or broken, since macOS reports that as "damaged".
echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Packaging ${DMG}..."
rm -rf "${STAGING_DIR}" "${DMG}"
mkdir -p "${STAGING_DIR}"
# ditto keeps the bundle (and its signature) intact.
ditto "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -format UDZO \
    -ov \
    "${DMG}"
rm -rf "${STAGING_DIR}"

echo ""
echo "==> DMG ready: ${DMG}"
