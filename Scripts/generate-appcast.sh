#!/usr/bin/env bash
#
# Generates and signs the Sparkle feed, .build/dist/appcast.xml.
#
# The private key only travels through standard input: it never touches the disk,
# the logs or the release assets. A missing key or any failed signature check
# exits non-zero, which stops the release (MoliSpec 007 §7.6.2).
#
# Environment:
#   SPARKLE_PRIVATE_KEY  Ed25519 private key (base64), required
#   SPARKLE_TOOLS_DIR    Sparkle tools (bin/generate_appcast, bin/sign_update), required

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
ARCHIVE_PATH="$DIST_DIR/$ZIP_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"

fail() {
    echo "generate-appcast.sh: $*" >&2
    exit 1
}

[ -f "$ARCHIVE_PATH" ] || fail "缺少更新包 $ARCHIVE_PATH"
[ -n "${SPARKLE_PRIVATE_KEY:-}" ] || fail "缺少 SPARKLE_PRIVATE_KEY；没有更新私钥不能发布"
GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/bin/generate_appcast"
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"
[ -x "$GENERATE_APPCAST" ] || fail "找不到 $GENERATE_APPCAST"
[ -x "$SIGN_UPDATE" ] || fail "找不到 $SIGN_UPDATE"

WORK_DIR="$(mktemp -d)"
trap 'find "$WORK_DIR" -delete 2>/dev/null || true' EXIT

# generate_appcast scans a directory; give it a copy so it leaves the dist folder alone.
mkdir -p "$WORK_DIR/archives"
ditto "$ARCHIVE_PATH" "$WORK_DIR/archives/$ZIP_NAME"
GENERATED="$WORK_DIR/appcast.xml"

# The feed lives at releases/latest, but each entry points at its own tag (MoliSpec 007).
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" \
    --maximum-deltas 0 \
    -o "$GENERATED" \
    "$WORK_DIR/archives"
[ -s "$GENERATED" ] || fail "generate_appcast 没有生成清单"

element() {
    sed -n "s|.*<sparkle:$1>\([^<]*\)</sparkle:$1>.*|\1|p" "$GENERATED" | head -n 1
}

FEED_SIGNATURE="$(sed -n 's|.*sparkle:edSignature="\([^"]*\)".*|\1|p' "$GENERATED" | head -n 1)"
[ -n "$FEED_SIGNATURE" ] || fail "清单里没有 sparkle:edSignature"

# Ed25519 is deterministic: signing the archive again must give the same bytes.
ARCHIVE_SIGNATURE="$(
    printf '%s' "$SPARKLE_PRIVATE_KEY" \
        | "$SIGN_UPDATE" -p --ed-key-file - "$ARCHIVE_PATH" \
        | head -n 1
)"
[ "$ARCHIVE_SIGNATURE" = "$FEED_SIGNATURE" ] || fail "清单里的签名和更新包重新计算的签名不一致"

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --verify --ed-key-file - "$GENERATED" > /dev/null \
    || fail "清单签名校验失败"

[ "$(element shortVersionString)" = "$VERSION" ] || fail "清单版本 $(element shortVersionString) 不是 $VERSION"
[ "$(element version)" = "$BUILD_NUMBER" ] || fail "清单构建号 $(element version) 不是 $BUILD_NUMBER"
grep -qF "/download/$TAG/$ZIP_NAME" "$GENERATED" || fail "清单的下载地址没有指向 $TAG/$ZIP_NAME"

# Only a fully checked feed goes into the dist folder.
remove_path "$APPCAST_PATH"
ditto "$GENERATED" "$APPCAST_PATH"
chmod 644 "$APPCAST_PATH"
echo "已生成并签名 ${APPCAST_PATH}（版本 ${VERSION}，构建号 ${BUILD_NUMBER}）"
