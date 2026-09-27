#!/usr/bin/env bash
#
# 从已经构建并签名的 bundle 生成 DMG。DMG 仅用于手动安装，Sparkle 更新使用 ZIP。
#
# 环境变量：APP_PATH、DIST_DIR

set -euo pipefail

APP_NAME="MoliSwitch"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/.build/$APP_NAME.app}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/.build/dist}"
DMG_ROOT="$ROOT_DIR/.build/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "$APP_PATH 不存在，请先运行 Scripts/build-app.sh。" >&2
    exit 1
fi

remove_path() {
    local path="$1"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    find "$path" -delete
}

remove_path "$DMG_ROOT"
remove_path "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
xattr -cr "$DMG_ROOT/$APP_NAME.app" 2>/dev/null || true

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

remove_path "$DMG_ROOT"

echo "已生成 $DMG_PATH"

