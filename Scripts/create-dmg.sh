#!/usr/bin/env bash
#
# Makes the DMG for manual installs from the built and signed app. Sparkle updates use the ZIP.

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG_ROOT="$ROOT_DIR/.build/dmg-root"
DMG_PATH="$DIST_DIR/$DMG_NAME"

[ -d "$APP_PATH" ] || { echo "$APP_PATH 不存在，先运行 Scripts/build-app.sh。" >&2; exit 1; }

remove_path "$DMG_ROOT"
remove_path "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$DIST_DIR"

ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" > /dev/null
remove_path "$DMG_ROOT"

echo "已生成 $DMG_PATH"
