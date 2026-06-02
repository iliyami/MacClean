#!/bin/bash
# Build, sign, notarize, and package Mac Clean as a DMG.
#
# Usage:
#   ./scripts/build-dmg.sh                    # Build with ad-hoc signing only
#   ./scripts/build-dmg.sh --notarize         # Sign with Developer ID + notarize + staple
#
# Environment variables for proper signing/notarization:
#   APPLE_DEVELOPER_ID  — "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE      — Keychain profile name (created via `xcrun notarytool store-credentials`)

set -euo pipefail

APP_NAME="Mac Clean"
BUNDLE_ID="com.macclean.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo '1.0.0')}"
# Multi-arch build emits the universal binary under .build/apple/Products/Release/
# instead of the single-arch .build/release/. Without this, Intel Macs (anything
# pre-Apple-Silicon, including the 2018 MBP A1989) launch the app and get
# "you can't open the application MacClean because PowerPC applications are
# no longer supported" — actually arm64 binaries get a similar refusal.
BUILD_DIR=".build/apple/Products/Release"
DMG_DIR=".build/dmg"
DMG_NAME="MacClean-${VERSION}.dmg"

# Detect signing capability
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

echo "=== Building Mac Clean v${VERSION} ==="
echo "Signing identity: $SIGNING_IDENTITY"
echo "Notarize: $NOTARIZE"
echo ""

# Step 1: Build release as a universal (arm64 + x86_64) binary
echo "[1/6] Building universal release binary (arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

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
    <string>Mac Clean Menu</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Clean Menu</string>
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
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
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

# Step 5: Create DMG
echo "[5/6] Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov -format UDZO \
    ".build/${DMG_NAME}" > /dev/null

# Sign the DMG too
if [[ "$NOTARIZE" == "true" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp ".build/${DMG_NAME}"
    echo "  → DMG signed with Developer ID"
fi

# Step 6: Notarize (optional)
if [[ "$NOTARIZE" == "true" ]]; then
    echo "[6/6] Submitting for notarization (may take 1-5 minutes)..."
    xcrun notarytool submit ".build/${DMG_NAME}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    echo "  → Stapling notarization ticket..."
    xcrun stapler staple ".build/${DMG_NAME}"
    xcrun stapler validate ".build/${DMG_NAME}"
    echo "  → Notarization complete"
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
