#!/bin/bash
# Build, sign, notarize, and package Mac Sai as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                    # Build with ad-hoc signing only
#   ./scripts/build-dmg.sh --notarize         # Sign with Developer ID + notarize + staple
#   ./scripts/build-dmg.sh --app-only         # Stop after the signed .app bundle (no DMG);
#                                             # used by scripts/dev-install.sh for fast local installs
#
# Environment variables for the build:
#   BUILD_ARCHS         — swift build arch flags (default: "--arch arm64 --arch x86_64").
#                         Override with "--arch $(uname -m)" for a fast native-only dev build.
#
# Environment variables for proper signing/notarization:
#   APPLE_DEVELOPER_ID  — "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE      — Keychain profile name (created via `xcrun notarytool store-credentials`)

set -euo pipefail

APP_NAME="Mac Sai"
BUNDLE_ID="com.macclean.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo '1.0.0')}"
# BUILD_DIR is resolved AFTER the build via `swift build --show-bin-path`:
# multi-arch builds emit to .build/apple/Products/Release/ while single-arch
# (BUILD_ARCHS override) emits to .build/<triple>/release/. Hardcoding one of
# them silently bundles stale binaries from the other (a 1.9.0 app shipped in
# a 1.10.0 wrapper during dev-install testing — binary and Info.plist drift).
DMG_DIR=".build/dmg"
DMG_NAME="MacSai-${VERSION}.dmg"

# Detect signing capability
APP_ONLY=false
if [[ "${1:-}" == "--app-only" ]]; then
    APP_ONLY=true
fi
NOTARIZE=false
SIGNING_IDENTITY="-"  # ad-hoc by default
if [[ "${1:-}" == "--notarize" ]]; then
    NOTARIZE=true
    if [[ -z "${APPLE_DEVELOPER_ID:-}" ]]; then
        echo "ERROR: --notarize requires APPLE_DEVELOPER_ID env var"
        echo "Example: export APPLE_DEVELOPER_ID='Developer ID Application: John Doe (ABC123XYZ)'"
        exit 1
    fi
    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        echo "ERROR: --notarize requires NOTARY_PROFILE env var"
        echo "Set it up first: xcrun notarytool store-credentials 'MacClean' --apple-id YOU@example.com --team-id TEAMID"
        exit 1
    fi
    SIGNING_IDENTITY="$APPLE_DEVELOPER_ID"
fi

echo "=== Building Mac Sai v${VERSION} ==="
echo "Signing identity: $SIGNING_IDENTITY"
echo "Notarize: $NOTARIZE"
echo ""

# Step 1: Build release as a universal (arm64 + x86_64) binary
BUILD_ARCHS="${BUILD_ARCHS:---arch arm64 --arch x86_64}"
echo "[1/6] Building release binaries (${BUILD_ARCHS})..."
swift build -c release ${BUILD_ARCHS} --product MacClean
swift build -c release ${BUILD_ARCHS} --product MacCleanMenu
BUILD_DIR=$(swift build -c release ${BUILD_ARCHS} --product MacClean --show-bin-path)
echo "  → Binaries: ${BUILD_DIR}"

# Step 2: Create .app bundle
echo "[2/6] Creating app bundle..."
APP_BUNDLE="${DMG_DIR}/${APP_NAME}.app"
rm -rf "${DMG_DIR}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/MacClean" "${APP_BUNDLE}/Contents/MacOS/"

cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacClean</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.macclean.deeplink</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>macclean</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

# Step 2.5: Nest the menu bar widget inside the main app as a LoginItem.
# SMAppService.loginItem(identifier:) expects the helper at this exact path
# (Contents/Library/LoginItems/<helper>.app), and the helper's bundle id
# is what gets passed to register(). LSUIElement=true keeps it off the
# Dock; it lives in the menu bar only.
echo "[2.5/6] Bundling MacCleanMenu widget..."
MENU_APP="${APP_BUNDLE}/Contents/Library/LoginItems/MacCleanMenu.app"
mkdir -p "${MENU_APP}/Contents/MacOS"
mkdir -p "${MENU_APP}/Contents/Resources"

cp "${BUILD_DIR}/MacCleanMenu" "${MENU_APP}/Contents/MacOS/"

cat > "${MENU_APP}/Contents/Info.plist" << MENU_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacCleanMenu</string>
    <key>CFBundleIdentifier</key>
    <string>com.macclean.menu</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mac Sai Menu</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Sai Menu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
MENU_PLIST

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${MENU_APP}/Contents/Resources/"
fi

# Step 3: Entitlements (needed for notarization with hardened runtime)
echo "[3/6] Creating entitlements..."
cat > "${DMG_DIR}/entitlements.plist" << ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Step 4: Sign the app
echo "[4/6] Signing app bundle..."
if [[ "$NOTARIZE" == "true" ]]; then
    codesign --force --deep --options runtime \
        --entitlements "${DMG_DIR}/entitlements.plist" \
        --sign "$SIGNING_IDENTITY" \
        --timestamp \
        "${APP_BUNDLE}"
    echo "  → Signed with Developer ID + hardened runtime"
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" "${APP_BUNDLE}"
    echo "  → Ad-hoc signed (no Developer ID provided)"
fi

# Verify signature
codesign --verify --verbose=1 "${APP_BUNDLE}" 2>&1 | head -3

# --app-only: stop here with the signed bundle (dev-install path).
if [[ "$APP_ONLY" == "true" ]]; then
    echo ""
    echo "=== App bundle ready (skipped DMG/notarization) ==="
    echo "App: ${APP_BUNDLE}"
    exit 0
fi

# Step 5: Create DMG
echo "[5/6] Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    ".build/${DMG_NAME}" > /dev/null

# Sign the DMG
if [[ "$NOTARIZE" == "true" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp ".build/${DMG_NAME}"
    echo "  → DMG signed with Developer ID"
fi

# Step 6: Notarize + staple the DMG ONLY. Notarizing the DMG also notarizes the
# app inside it (Apple scans the contents), so one submission covers both. We do
# not separately notarize the app: that doubled the Apple round-trips and was the
# step that hung for ~1h. The copied-out app launches via a quick online
# Gatekeeper check on first run, which is fine for Homebrew/DMG installs.
if [[ "$NOTARIZE" == "true" ]]; then
    echo "[6/6] Notarizing DMG..."
    xcrun notarytool submit ".build/${DMG_NAME}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    xcrun stapler staple ".build/${DMG_NAME}"
    xcrun stapler validate ".build/${DMG_NAME}"
    echo "  → Notarization complete (DMG stapled; app inside notarized)"
else
    echo "[6/6] Skipping notarization (no --notarize flag)"
fi

# Compute SHA256 for Homebrew Cask
SHA256=$(shasum -a 256 ".build/${DMG_NAME}" | awk '{print $1}')

echo ""
echo "=== Build complete ==="
echo "DMG:    .build/${DMG_NAME}"
echo "Size:   $(du -h ".build/${DMG_NAME}" | cut -f1)"
echo "SHA256: ${SHA256}"
