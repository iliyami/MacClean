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
    red "Mac Sai 需要 macOS 14 (Sonoma) 或更高版本。当前系统版本为 $(sw_vers -productVersion)。"
    exit 1
fi

cyan "正在获取最新版本信息..."
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
DMG_URL=$(echo "$LATEST" | grep -oE '"browser_download_url":\s*"[^"]+\.dmg"' | head -1 | cut -d'"' -f4)
VERSION=$(echo "$LATEST" | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | cut -d'"' -f4)

if [ -z "$DMG_URL" ]; then
    red "在最新 Release 中找不到 DMG，已中止。"
    exit 1
fi

cyan "正在下载 Mac Sai $VERSION..."
TMP=$(mktemp -d)
DMG_PATH="$TMP/macclean.dmg"
curl -fsSL "$DMG_URL" -o "$DMG_PATH"

cyan "正在挂载 DMG..."
MOUNT=$(hdiutil attach -nobrowse -quiet "$DMG_PATH" | grep "/Volumes/" | awk '{print $NF}')
if [ -z "$MOUNT" ]; then
    red "DMG 挂载失败。"
    exit 1
fi

cyan "正在安装到 $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi
cp -R "$MOUNT/$APP_NAME" "$INSTALL_DIR/"

cyan "正在清理临时文件..."
hdiutil detach -quiet "$MOUNT"
rm -rf "$TMP"

# Mac Sai is notarized by Apple, so no quarantine workaround is needed.

green ""
green "✓ Mac Sai $VERSION 已安装到 $INSTALL_DIR/$APP_NAME"
green ""
echo "启动命令：open \"$INSTALL_DIR/$APP_NAME\""
echo ""
echo "如需扫描邮件、Safari 和隐私项目，请授予完全磁盘访问权限："
echo "  系统设置 → 隐私与安全性 → 完全磁盘访问权限"
