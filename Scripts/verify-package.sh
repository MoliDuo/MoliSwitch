#!/usr/bin/env bash
#
# 校验发布产物是否可以安全地作为 Sparkle 更新源发布。
#
# 覆盖内容：产物文件、校验和、构建清单、Info.plist 更新键、双架构、
# Sparkle.framework 结构、签名、加载路径，以及 ZIP 与 DMG 内容一致。
#
# 用法：Scripts/verify-package.sh [DIST_DIR]
# 环境变量：VERSION、BUILD_NUMBER、UNIVERSAL（默认 1）

set -euo pipefail

APP_NAME="AutoInputSwitcher"
BUNDLE_IDENTIFIER="com.local.AutoInputSwitcher"
MINIMUM_SYSTEM_VERSION="14.0"
UNIVERSAL="${UNIVERSAL:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="${1:-$ROOT_DIR/.build/dist}"

ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"
CHECKSUMS_PATH="$DIST_DIR/checksums.txt"
MANIFEST_PATH="$DIST_DIR/build-manifest.json"
PUBLIC_KEY_FILE="$ROOT_DIR/Config/SparklePublicKey.txt"

WORK_DIR="$(mktemp -d)"
MOUNT_POINT="$WORK_DIR/dmg"
DMG_ATTACHED=0

cleanup() {
    if [ "$DMG_ATTACHED" = "1" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet > /dev/null 2>&1 ||
            hdiutil detach "$MOUNT_POINT" -force -quiet > /dev/null 2>&1 ||
            true
    fi

    if [ -d "$WORK_DIR" ]; then
        find "$WORK_DIR" -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

section() {
    printf '\n== %s ==\n' "$1"
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok   %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL %s\n' "$1"
}

check() {
    local description="$1"
    shift

    if "$@" > /dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

check_contains() {
    local description="$1"
    local needle="$2"
    shift 2

    if "$@" 2>/dev/null | grep -F -- "$needle" > /dev/null; then
        pass "$description"
    else
        fail "$description"
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

check_plist_value() {
    local description="$1"
    local key="$2"
    local expected="$3"
    local plist="$4"
    local actual

    actual="$(plist_value "$key" "$plist")"

    if [ "$actual" = "$expected" ]; then
        pass "$description"
    else
        fail "${description}（期望 ${expected}，实际 ${actual:-<空>}）"
    fi
}

check_no_build_paths() {
    local description="$1"
    local binary="$2"

    if otool -l "$binary" 2>/dev/null | grep '\.build' > /dev/null; then
        fail "$description"
    else
        pass "$description"
    fi
}

# 逐文件列出内容指纹，用来比较 ZIP 与 DMG 中的同一份应用。
tree_fingerprint() {
    local root="$1"

    (
        cd "$root" || exit 1
        find . -print | LC_ALL=C sort | while IFS= read -r entry; do
            if [ -L "$entry" ]; then
                printf 'link %s -> %s\n' "$entry" "$(readlink "$entry")"
            elif [ -d "$entry" ]; then
                printf 'dir  %s\n' "$entry"
            else
                printf 'file %s %s\n' "$entry" "$(shasum -a 256 "$entry" | awk '{print $1}')"
            fi
        done
    )
}

section "产物文件"

check "$APP_NAME-macOS.zip 存在且非空" test -s "$ZIP_PATH"
check "$APP_NAME-macOS.dmg 存在且非空" test -s "$DMG_PATH"
check "checksums.txt 存在且非空" test -s "$CHECKSUMS_PATH"
check "build-manifest.json 存在且非空" test -s "$MANIFEST_PATH"

if [ ! -s "$ZIP_PATH" ] || [ ! -s "$DMG_PATH" ] || [ ! -s "$CHECKSUMS_PATH" ] || [ ! -s "$MANIFEST_PATH" ]; then
    printf '\n缺少必要的产物文件，无法继续校验。\n' >&2
    exit 1
fi

section "校验和"

if (cd "$DIST_DIR" && shasum -a 256 -c checksums.txt > /dev/null 2>&1); then
    pass "checksums.txt 中的校验和全部匹配"
else
    fail "checksums.txt 校验失败"
fi

section "构建清单"

check "build-manifest.json 是合法 JSON" jq -e . "$MANIFEST_PATH"

MANIFEST_VERSION="$(jq -r '.version // empty' "$MANIFEST_PATH" 2>/dev/null || true)"
MANIFEST_BUILD_NUMBER="$(jq -r '.buildNumber // empty' "$MANIFEST_PATH" 2>/dev/null || true)"
MANIFEST_TAG="$(jq -r '.tag // empty' "$MANIFEST_PATH" 2>/dev/null || true)"

if [ -z "$MANIFEST_VERSION" ] || [ -z "$MANIFEST_BUILD_NUMBER" ] || [ -z "$MANIFEST_TAG" ]; then
    fail "清单缺少 version / buildNumber / tag"
else
    pass "清单版本为 ${MANIFEST_VERSION}（构建号 ${MANIFEST_BUILD_NUMBER}，tag ${MANIFEST_TAG}）"
fi

if [ -z "${VERSION:-}" ]; then
    :
elif [ "$MANIFEST_VERSION" != "$VERSION" ]; then
    fail "清单版本 $MANIFEST_VERSION 与环境变量 VERSION=$VERSION 不一致"
else
    pass "清单版本与环境变量 VERSION 一致"
fi

if [ -z "${BUILD_NUMBER:-}" ]; then
    :
elif [ "$MANIFEST_BUILD_NUMBER" != "$BUILD_NUMBER" ]; then
    fail "清单构建号 $MANIFEST_BUILD_NUMBER 与环境变量 BUILD_NUMBER=$BUILD_NUMBER 不一致"
else
    pass "清单构建号与环境变量 BUILD_NUMBER 一致"
fi

manifest_file_hash() {
    jq -r --arg name "$1" '.files[]? | select(.name == $name) | .sha256' "$MANIFEST_PATH" 2>/dev/null | head -n 1
}

for artifact_name in "$APP_NAME-macOS.zip" "$APP_NAME-macOS.dmg"; do
    expected_hash="$(manifest_file_hash "$artifact_name")"
    actual_hash="$(shasum -a 256 "$DIST_DIR/$artifact_name" | awk '{print $1}')"

    if [ -n "$expected_hash" ] && [ "$expected_hash" = "$actual_hash" ]; then
        pass "清单中 $artifact_name 的 sha256 与实际文件一致"
    else
        fail "清单中 $artifact_name 的 sha256 与实际文件不一致"
    fi
done

section "ZIP 内容"

ZIP_ROOT="$WORK_DIR/zip"
mkdir -p "$ZIP_ROOT"

check "ZIP 可以解压" ditto -x -k "$ZIP_PATH" "$ZIP_ROOT"

ZIP_APP="$ZIP_ROOT/$APP_NAME.app"

if [ ! -d "$ZIP_APP" ]; then
    fail "ZIP 中没有 $APP_NAME.app，跳过后续内容校验"
    printf '\n通过 %s 项，失败 %s 项\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
    exit 1
fi

pass "ZIP 中包含 $APP_NAME.app"

section "Info.plist"

PLIST="$ZIP_APP/Contents/Info.plist"

check "存在 Contents/Info.plist" test -f "$PLIST"

check_plist_value "CFBundleIdentifier" "CFBundleIdentifier" "$BUNDLE_IDENTIFIER" "$PLIST"
check_plist_value "CFBundleShortVersionString 与清单版本一致" "CFBundleShortVersionString" "$MANIFEST_VERSION" "$PLIST"
check_plist_value "CFBundleVersion 与清单构建号一致" "CFBundleVersion" "$MANIFEST_BUILD_NUMBER" "$PLIST"
check_plist_value "LSMinimumSystemVersion" "LSMinimumSystemVersion" "$MINIMUM_SYSTEM_VERSION" "$PLIST"
check_plist_value "LSUIElement" "LSUIElement" "true" "$PLIST"

check_plist_value "SUEnableAutomaticChecks" "SUEnableAutomaticChecks" "true" "$PLIST"
check_plist_value "SUScheduledCheckInterval" "SUScheduledCheckInterval" "3600" "$PLIST"
check_plist_value "SUAutomaticallyUpdate" "SUAutomaticallyUpdate" "false" "$PLIST"
check_plist_value "SUAllowsAutomaticUpdates" "SUAllowsAutomaticUpdates" "false" "$PLIST"
check_plist_value "SUEnableSystemProfiling" "SUEnableSystemProfiling" "false" "$PLIST"
check_plist_value "SUVerifyUpdateBeforeExtraction" "SUVerifyUpdateBeforeExtraction" "true" "$PLIST"
check_plist_value "SURequireSignedFeed" "SURequireSignedFeed" "true" "$PLIST"
check_plist_value "SUSignedFeedFailureExpirationInterval" "SUSignedFeedFailureExpirationInterval" "0" "$PLIST"

FEED_URL_VALUE="$(plist_value "SUFeedURL" "$PLIST")"

case "$FEED_URL_VALUE" in
    https://*/appcast.xml)
        pass "SUFeedURL 是 https 的 appcast.xml 地址"
        ;;
    *)
        fail "SUFeedURL 不是 https 的 appcast.xml 地址：$FEED_URL_VALUE"
        ;;
esac

case "$FEED_URL_VALUE" in
    *releases/latest/download/appcast.xml)
        pass "SUFeedURL 指向 releases/latest/download/appcast.xml"
        ;;
    *)
        fail "SUFeedURL 必须指向 releases/latest/download/appcast.xml：$FEED_URL_VALUE"
        ;;
esac

PLIST_PUBLIC_KEY="$(plist_value "SUPublicEDKey" "$PLIST")"

if printf '%s' "$PLIST_PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
    pass "SUPublicEDKey 是 32 字节 Ed25519 公钥的 base64"
else
    fail "SUPublicEDKey 格式不正确：$PLIST_PUBLIC_KEY"
fi

if [ -f "$PUBLIC_KEY_FILE" ]; then
    FILE_PUBLIC_KEY="$(sed -e 's/#.*$//' "$PUBLIC_KEY_FILE" | tr -d '[:space:]' | head -n 1)"

    if [ -n "$FILE_PUBLIC_KEY" ] && [ "$FILE_PUBLIC_KEY" = "$PLIST_PUBLIC_KEY" ]; then
        pass "SUPublicEDKey 与 Config/SparklePublicKey.txt 一致"
    else
        fail "SUPublicEDKey 与 Config/SparklePublicKey.txt 不一致"
    fi
else
    fail "缺少 ${PUBLIC_KEY_FILE}，无法确认公钥来源"
fi

section "架构"

BINARY="$ZIP_APP/Contents/MacOS/$APP_NAME"
FRAMEWORK="$ZIP_APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_BINARY="$FRAMEWORK/Versions/B/Sparkle"

check "存在主可执行文件" test -x "$BINARY"

if [ "$UNIVERSAL" = "1" ]; then
    check_contains "主可执行文件包含 arm64" "arm64" lipo -archs "$BINARY"
    check_contains "主可执行文件包含 x86_64" "x86_64" lipo -archs "$BINARY"
fi

section "Sparkle.framework"

check "存在 Contents/Frameworks/Sparkle.framework" test -d "$FRAMEWORK"
check "Versions/Current 是符号链接" test -L "$FRAMEWORK/Versions/Current"
check "framework 根目录 Sparkle 是符号链接" test -L "$FRAMEWORK/Sparkle"
check "framework 根目录 Autoupdate 是符号链接" test -L "$FRAMEWORK/Autoupdate"
check "framework 根目录 Updater.app 是符号链接" test -L "$FRAMEWORK/Updater.app"
check "存在 Sparkle 动态库" test -f "$SPARKLE_BINARY"
check "存在可执行的 Autoupdate" test -x "$FRAMEWORK/Versions/B/Autoupdate"
check "存在可执行的 Updater.app/Contents/MacOS/Updater" test -x "$FRAMEWORK/Versions/B/Updater.app/Contents/MacOS/Updater"
check "存在 Downloader.xpc" test -d "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
check "存在 Installer.xpc" test -d "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
check "存在 Resources/Info.plist" test -f "$FRAMEWORK/Versions/B/Resources/Info.plist"

if [ "$UNIVERSAL" = "1" ] && [ -f "$SPARKLE_BINARY" ]; then
    check_contains "Sparkle 动态库包含 arm64" "arm64" lipo -archs "$SPARKLE_BINARY"
    check_contains "Sparkle 动态库包含 x86_64" "x86_64" lipo -archs "$SPARKLE_BINARY"
fi

section "签名"

check "应用签名通过深度校验" codesign --verify --deep --strict "$ZIP_APP"
check "Sparkle.framework 签名有效" codesign --verify --strict "$FRAMEWORK"

for helper in \
    "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app" \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"; do
    check "签名有效：$(basename "$helper")" codesign --verify --strict "$helper"
done

section "加载路径"

check_no_build_paths "主可执行文件没有构建目录加载路径" "$BINARY"
check_no_build_paths "Sparkle 动态库没有构建目录加载路径" "$SPARKLE_BINARY"
check_contains "主可执行文件链接了 Sparkle.framework" "Sparkle.framework" otool -L "$BINARY"
check_contains "主可执行文件包含 @executable_path/../Frameworks" "@executable_path/../Frameworks" otool -l "$BINARY"

section "DMG 内容"

mkdir -p "$MOUNT_POINT"

if hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" > /dev/null 2>&1; then
    DMG_ATTACHED=1
    pass "DMG 可以挂载"
else
    fail "DMG 无法挂载"
fi

if [ "$DMG_ATTACHED" = "1" ]; then
    DMG_APP="$MOUNT_POINT/$APP_NAME.app"

    check "DMG 中包含 $APP_NAME.app" test -d "$DMG_APP"

    if [ -L "$MOUNT_POINT/Applications" ] && [ "$(readlink "$MOUNT_POINT/Applications")" = "/Applications" ]; then
        pass "DMG 中包含指向 /Applications 的符号链接"
    else
        fail "DMG 中缺少指向 /Applications 的符号链接"
    fi

    if [ -d "$DMG_APP" ]; then
        ZIP_FINGERPRINT="$WORK_DIR/zip-fingerprint.txt"
        DMG_FINGERPRINT="$WORK_DIR/dmg-fingerprint.txt"

        tree_fingerprint "$ZIP_APP" > "$ZIP_FINGERPRINT"
        tree_fingerprint "$DMG_APP" > "$DMG_FINGERPRINT"

        if diff -u "$ZIP_FINGERPRINT" "$DMG_FINGERPRINT" > "$WORK_DIR/fingerprint.diff"; then
            pass "ZIP 与 DMG 中的应用内容完全一致"
        else
            fail "ZIP 与 DMG 中的应用内容不一致"
            head -n 20 "$WORK_DIR/fingerprint.diff" || true
        fi
    fi
fi

section "结果"

printf '通过 %s 项，失败 %s 项\n' "$PASS_COUNT" "$FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '打包校验未通过，已阻止发布。\n' >&2
    exit 1
fi

printf '打包校验通过。\n'
