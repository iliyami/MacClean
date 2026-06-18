#!/bin/bash
# One-line installer for Mac Sai.
# Usage: curl -fsSL https://raw.githubusercontent.com/iliyami/MacSai/main/scripts/install.sh | bash

set -euo pipefail

REPO="iliyami/MacSai"
APP_NAME="Mac Sai.app"
INSTALL_DIR="/Applications"

cyan() { printf "\033[36m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

# Check macOS version
OS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [ "$OS_VERSION" -lt 14 ]; then
    red "Mac Sai requires macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."
    exit 1
fi

cyan "Fetching latest release info..."
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
DMG_URL=$(echo "$LATEST" | grep -oE '"browser_download_url":\s*"[^"]+\.dmg"' | head -1 | cut -d'"' -f4)
VERSION=$(echo "$LATEST" | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | cut -d'"' -f4)

if [ -z "$DMG_URL" ]; then
    red "Could not find a DMG in the latest release. Aborting."
    exit 1
fi

cyan "Downloading Mac Sai $VERSION..."
TMP=$(mktemp -d)
DMG_PATH="$TMP/macclean.dmg"
curl -fsSL "$DMG_URL" -o "$DMG_PATH"

cyan "Mounting DMG..."
MOUNT=$(hdiutil attach -nobrowse -quiet "$DMG_PATH" | grep "/Volumes/" | awk '{print $NF}')
if [ -z "$MOUNT" ]; then
    red "Failed to mount the DMG."
    exit 1
fi

cyan "Installing to $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi
cp -R "$MOUNT/$APP_NAME" "$INSTALL_DIR/"

cyan "Cleaning up..."
hdiutil detach -quiet "$MOUNT"
rm -rf "$TMP"

# Mac Sai is notarized by Apple, so no quarantine workaround is needed.

green ""
green "✓ Mac Sai $VERSION installed to $INSTALL_DIR/$APP_NAME"
green ""
echo "Launch with: open \"$INSTALL_DIR/$APP_NAME\""
echo ""
echo "For Mail, Safari, and Privacy scans, grant Full Disk Access:"
echo "  System Settings → Privacy & Security → Full Disk Access"
