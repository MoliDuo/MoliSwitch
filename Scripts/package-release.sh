#!/usr/bin/env bash
#
# Packages a release: the ZIP (for Sparkle, bundle structure kept), the DMG (for
# manual installs) and SHA256SUMS. Both come from the same signed app.
#
# Environment: CONFIGURATION, UNIVERSAL, SIGN_IDENTITY, SIGN_KEYCHAIN (passed on to build-app.sh)

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

"$ROOT_DIR/Scripts/build-app.sh"

remove_path "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ditto keeps symlinks, permissions and the bundle structure, which Sparkle needs.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"
"$ROOT_DIR/Scripts/create-dmg.sh"

(
    cd "$DIST_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS > /dev/null
)

echo "已打包 $DIST_DIR/$ZIP_NAME"
echo "已打包 $DIST_DIR/$DMG_NAME"
