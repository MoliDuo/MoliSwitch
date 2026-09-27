#!/usr/bin/env bash
#
# 打包一个可发布版本：ZIP（Sparkle 更新用，保留 bundle 结构）、DMG（手动安装用）、
# 校验和以及构建清单。ZIP 与 DMG 都来自同一个已签名 bundle。
#
# 环境变量：VERSION、BUILD_NUMBER、TAG、CONFIGURATION、SIGN_IDENTITY、SIGN_KEYCHAIN、UNIVERSAL

set -euo pipefail

APP_NAME="MoliSwitch"
BUNDLE_IDENTIFIER="com.moli.MoliSwitch"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
TAG="${TAG:-build-${BUILD_NUMBER%%.*}-${BUILD_NUMBER##*.}}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/.build/dist"
ZIP_NAME="$APP_NAME-macOS.zip"
DMG_NAME="$APP_NAME-macOS.dmg"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"

cd "$ROOT_DIR"

fail() {
    echo "package-release.sh: $*" >&2
    exit 1
}

remove_path() {
    local path="$1"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    find "$path" -delete
}

VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
CONFIGURATION="$CONFIGURATION" \
SIGN_IDENTITY="$SIGN_IDENTITY" \
SIGN_KEYCHAIN="$SIGN_KEYCHAIN" \
    "$ROOT_DIR/Scripts/build-app.sh"

[ -d "$APP_PATH" ] || fail "缺少构建产物 $APP_PATH"

remove_path "$DIST_DIR"
mkdir -p "$DIST_DIR"

xattr -cr "$APP_PATH" 2>/dev/null || true

# ditto 保留符号链接、可执行权限和 bundle 结构，Sparkle 需要这样的 ZIP。
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

APP_PATH="$APP_PATH" DIST_DIR="$DIST_DIR" "$ROOT_DIR/Scripts/create-dmg.sh"

[ -s "$ZIP_PATH" ] || fail "ZIP 未生成：$ZIP_PATH"
[ -s "$DMG_PATH" ] || fail "DMG 未生成：$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > checksums.txt
    shasum -a 256 -c checksums.txt > /dev/null
)

zip_sha="$(awk -v name="$ZIP_NAME" '$2 == name {print $1}' "$DIST_DIR/checksums.txt")"
dmg_sha="$(awk -v name="$DMG_NAME" '$2 == name {print $1}' "$DIST_DIR/checksums.txt")"
[ -n "$zip_sha" ] || fail "无法计算 $ZIP_NAME 的校验和"
[ -n "$dmg_sha" ] || fail "无法计算 $DMG_NAME 的校验和"

zip_size="$(stat -f%z "$ZIP_PATH")"
dmg_size="$(stat -f%z "$DMG_PATH")"
git_sha="${GITHUB_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)}"
run_id="${GITHUB_RUN_ID:-local}"
run_attempt="${GITHUB_RUN_ATTEMPT:-0}"

cat > "$DIST_DIR/build-manifest.json" <<MANIFEST_EOF
{
  "appName": "$APP_NAME",
  "bundleIdentifier": "$BUNDLE_IDENTIFIER",
  "version": "$VERSION",
  "buildNumber": "$BUILD_NUMBER",
  "tag": "$TAG",
  "gitSha": "$git_sha",
  "runId": "$run_id",
  "runAttempt": "$run_attempt",
  "minimumSystemVersion": "14.0",
  "architectures": ["arm64", "x86_64"],
  "files": [
    {"name": "$ZIP_NAME", "role": "sparkle-update", "sha256": "$zip_sha", "size": $zip_size},
    {"name": "$DMG_NAME", "role": "manual-install", "sha256": "$dmg_sha", "size": $dmg_size}
  ],
  "checksums": "checksums.txt"
}
MANIFEST_EOF

echo "已打包 $ZIP_PATH"
echo "已打包 $DMG_PATH"
echo "版本 ${VERSION}（构建号 ${BUILD_NUMBER}，tag ${TAG}）"

