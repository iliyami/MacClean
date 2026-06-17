#!/bin/bash
# Fast local install for development: build the app bundle (native arch only,
# ad-hoc signed, no DMG/notarization) and replace /Applications/Mac Sai.app
# with it. For checking a branch build on your own machine in about a minute;
# real releases still go through build-dmg.sh --notarize in CI.
#
# Usage: ./scripts/dev-install.sh

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mac Sai"
APP_BUNDLE=".build/dmg/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

# Show exactly what is being installed: the current checkout (unmerged
# work and uncommitted edits included), compiled with -c release
# (optimization level, not the published GitHub release).
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
DIRTY=$(git status --porcelain 2>/dev/null | head -1 | grep -q . && echo " + uncommitted changes" || true)
echo "=== Dev install: building current checkout [${BRANCH}${DIRTY}] v$(tr -d '[:space:]' < VERSION) ($(uname -m), ad-hoc signed) ==="
BUILD_ARCHS="--arch $(uname -m)" ./scripts/build-dmg.sh --app-only

# Re-sign with the Developer ID (a stable identity) so Full Disk Access and other
# TCC grants survive across dev builds. Ad-hoc signatures change every build, so
# macOS treats each install as a brand-new app and re-prompts file-by-file. The
# first build after switching identities still needs one fresh FDA grant.
DEVID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "${DEVID}" ]; then
    echo "Re-signing with: ${DEVID}"
    if codesign --force --deep --sign "${DEVID}" "${APP_BUNDLE}" >/dev/null 2>&1; then
        echo "  → stable signature applied (FDA persists across dev builds)"
    else
        echo "  → re-sign failed; staying ad-hoc (FDA will re-prompt)"
    fi
else
    echo "No Developer ID Application identity found; ad-hoc signed (FDA re-prompts each build)."
fi

# Quit the running app and its menu bar helper before swapping the bundle.
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x MacCleanMenu 2>/dev/null || true
pkill -x MacClean 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}..."
rm -rf "${DEST}"
ditto "${APP_BUNDLE}" "${DEST}"

echo "Launching..."
open "${DEST}"

echo ""
echo "Done. Notes:"
echo "  - This build is ad-hoc signed; its signature differs from the notarized"
echo "    release, so macOS may ask you to re-grant Full Disk Access"
echo "    (System Settings -> Privacy & Security -> Full Disk Access)."
echo "  - A later 'brew upgrade --cask mac-sai' will overwrite this dev build."
