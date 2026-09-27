#!/usr/bin/env bash
#
# 生成并签名 Sparkle 更新清单 appcast.xml。
#
# 私钥只经由标准输入使用，不落盘、不进日志、不进构建产物。
# 缺少私钥，或任何一步签名校验失败，都会以非零状态退出，从而阻断发布。
#
# 环境变量：
#   SPARKLE_PRIVATE_KEY  Ed25519 私钥（generate_keys -x 导出的 base64），必填
#   SPARKLE_TOOLS_DIR    Sparkle 工具目录（含 bin/generate_appcast），必填
#   TAG                  版本 tag，必填；清单里的下载地址使用它，禁止使用 latest
#   DIST_DIR             产物目录，默认 .build/dist
#   VERSION              可选，显示版本，用于核对清单
#   BUILD_NUMBER         可选，构建号，用于核对清单
#   APP_NAME             应用名，默认 MoliSwitch
#   GITHUB_REPOSITORY    仓库，默认 MoliDuo/MoliSwitch

set -euo pipefail

APP_NAME="${APP_NAME:-MoliSwitch}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/.build/dist}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
REPOSITORY="${GITHUB_REPOSITORY:-MoliDuo/MoliSwitch}"
TAG="${TAG:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

ARCHIVE_NAME="$APP_NAME-macOS.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"

fail() {
    echo "generate-appcast.sh: $*" >&2
    exit 1
}

[ -n "$TAG" ] || fail "缺少 TAG；清单的下载地址必须指向具体版本 tag"
[ "$TAG" != "latest" ] || fail "TAG 不能是 latest，否则清单和安装包版本会错配"
[ -f "$ARCHIVE_PATH" ] || fail "缺少更新包 $ARCHIVE_PATH"
[ -n "$SPARKLE_TOOLS_DIR" ] || fail "缺少 SPARKLE_TOOLS_DIR（Sparkle 工具目录）"

GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/bin/generate_appcast"
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"

[ -x "$GENERATE_APPCAST" ] || fail "找不到可执行的 $GENERATE_APPCAST"
[ -x "$SIGN_UPDATE" ] || fail "找不到可执行的 $SIGN_UPDATE"
[ -n "${SPARKLE_PRIVATE_KEY:-}" ] || fail "缺少 SPARKLE_PRIVATE_KEY；未配置更新私钥时不得发布"

WORK_DIR="$(mktemp -d)"
cleanup() {
    if [ -d "$WORK_DIR" ]; then
        find "$WORK_DIR" -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT

# generate_appcast 以目录为单位扫描更新包，这里用副本，避免它在产物目录里创建 old_updates。
ARCHIVES_DIR="$WORK_DIR/archives"
mkdir -p "$ARCHIVES_DIR"
ditto "$ARCHIVE_PATH" "$ARCHIVES_DIR/$ARCHIVE_NAME"

DOWNLOAD_URL_PREFIX="https://github.com/$REPOSITORY/releases/download/$TAG/"
GENERATED_APPCAST="$WORK_DIR/appcast.xml"

echo "使用版本 tag $TAG 生成更新清单"

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    --maximum-deltas 0 \
    -o "$GENERATED_APPCAST" \
    "$ARCHIVES_DIR"

[ -s "$GENERATED_APPCAST" ] || fail "generate_appcast 没有生成清单"

# 读取清单里某个 sparkle 元素的值。
appcast_element() {
    local name="$1"

    sed -n "s|.*<sparkle:$name>\([^<]*\)</sparkle:$name>.*|\1|p" "$GENERATED_APPCAST" | head -n 1
}

# 读取清单里更新包的 Ed25519 签名。
appcast_signature() {
    sed -n 's|.*sparkle:edSignature="\([^"]*\)".*|\1|p' "$GENERATED_APPCAST" | head -n 1
}

MANIFEST_SIGNATURE="$(appcast_signature)"
[ -n "$MANIFEST_SIGNATURE" ] || fail "清单中没有 sparkle:edSignature，更新包没有签名"

# 用私钥重新计算签名：Ed25519 对同一份数据是确定性的，两者必须逐字节一致。
ARCHIVE_SIGNATURE="$(
    printf '%s' "$SPARKLE_PRIVATE_KEY" |
        "$SIGN_UPDATE" -p --ed-key-file - "$ARCHIVE_PATH" |
        sed -n 's|.*edSignature="\([^"]*\)".*|\1|p; s|^\([A-Za-z0-9+/]\{80,\}=*\)$|\1|p' |
        head -n 1
)"

printf '%s' "$ARCHIVE_SIGNATURE" | grep -Eq '^[A-Za-z0-9+/]{86}==$' \
    || fail "sign_update 没有返回有效的 Ed25519 签名"

[ "$ARCHIVE_SIGNATURE" = "$MANIFEST_SIGNATURE" ] \
    || fail "清单中的签名与重新计算的更新包签名不一致"

# 校验清单自身的签名。CI 里没有登录钥匙串，所以私钥必须再次经标准输入传入。
verify_appcast_signature() {
    if printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --verify --ed-key-file - "$GENERATED_APPCAST" > /dev/null 2>&1; then
        return 0
    fi

    if "$SIGN_UPDATE" --verify "$GENERATED_APPCAST" > /dev/null 2>&1; then
        return 0
    fi

    return 1
}

verify_appcast_signature || fail "清单签名校验失败"

FEED_SHORT_VERSION="$(appcast_element shortVersionString)"
FEED_VERSION="$(appcast_element version)"

[ -n "$FEED_SHORT_VERSION" ] || fail "清单缺少 sparkle:shortVersionString"
[ -n "$FEED_VERSION" ] || fail "清单缺少 sparkle:version"

if [ -n "$VERSION" ] && [ "$FEED_SHORT_VERSION" != "$VERSION" ]; then
    fail "清单显示版本 $FEED_SHORT_VERSION 与 VERSION=$VERSION 不一致"
fi

if [ -n "$BUILD_NUMBER" ] && [ "$FEED_VERSION" != "$BUILD_NUMBER" ]; then
    fail "清单构建号 $FEED_VERSION 与 BUILD_NUMBER=$BUILD_NUMBER 不一致"
fi

if grep -q 'releases/latest/' "$GENERATED_APPCAST"; then
    fail "清单包含 latest 下载地址；更新包必须指向具体版本 tag"
fi

if ! grep -qF "/download/$TAG/" "$GENERATED_APPCAST"; then
    fail "清单中没有指向 tag $TAG 的下载地址"
fi

# 全部校验通过后才把清单放进产物目录：绝不留下未签名的清单。
if [ -e "$APPCAST_PATH" ]; then
    find "$APPCAST_PATH" -delete
fi

ditto "$GENERATED_APPCAST" "$APPCAST_PATH"
chmod 644 "$APPCAST_PATH"

echo "已生成并签名 ${APPCAST_PATH}（版本 ${FEED_SHORT_VERSION}，构建号 ${FEED_VERSION}）"
