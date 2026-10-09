# shellcheck shell=bash
#
# Shared names and version numbers for the build scripts. Source it, don't run it.
#
# The version lives only in the VERSION file at the repository root (MoliSpec 006).
# CFBundleVersion is derived from it: X*1000000 + Y*1000 + Z, so it only ever grows.
# Builds up to 0.2.41 used "<run>.<attempt>" (41.1 at most); 0.3.0 is 3000, which
# Sparkle orders after them.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="MoliSwitch"
DISPLAY_NAME="Moli Switch"
# Kept from before MoliSpec: a new identifier would cut installed apps off from
# updates and reset their Accessibility grant (see the exception in moli.yaml).
BUNDLE_IDENTIFIER="com.moli.MoliSwitch"
MINIMUM_SYSTEM_VERSION="14.0"
REPOSITORY="${GITHUB_REPOSITORY:-MoliDuo/MoliSwitch}"
FEED_URL="https://github.com/$REPOSITORY/releases/latest/download/appcast.xml"
# Universal binary: macOS 14 still runs on Intel Macs.
ARCHES=(arm64 x86_64)
ARCH_LABEL="universal"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
if ! [[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "VERSION 文件不是 X.Y.Z：$VERSION" >&2
    exit 1
fi
BUILD_NUMBER="$((BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3]))"
TAG="v$VERSION"

APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
ASSET_BASE="${APP_NAME}_${VERSION}_macos_${ARCH_LABEL}"
ZIP_NAME="$ASSET_BASE.zip"
DMG_NAME="$ASSET_BASE.dmg"

PUBLIC_KEY_FILE="$ROOT_DIR/Config/SparklePublicKey.txt"
SIGNING_CERTIFICATE_FILE="$ROOT_DIR/Config/CodeSigningCertificate.txt"

# Deletes a file or directory tree if it exists.
remove_path() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        find "$1" -delete
    fi
}

sparkle_public_key() {
    sed -e 's/#.*$//' "$PUBLIC_KEY_FILE" | tr -d '[:space:]' | head -n 1
}
