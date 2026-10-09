#!/usr/bin/env bash
#
# Checks the packaged release before it can be published (MoliSpec 006 §6.5.2):
# files and checksums, Info.plist and update keys, architecture, Sparkle.framework,
# signatures, load paths, and that the ZIP and the DMG hold the same app.
#
# Environment:
#   REQUIRE_SIGNING_CERTIFICATE  1 requires the shared certificate in
#                                Config/CodeSigningCertificate.txt (the release workflow sets it)

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REQUIRE_SIGNING_CERTIFICATE="${REQUIRE_SIGNING_CERTIFICATE:-0}"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"

WORK_DIR="$(mktemp -d)"
MOUNT_POINT="$WORK_DIR/dmg"
DMG_ATTACHED=0

cleanup() {
    if [ "$DMG_ATTACHED" = "1" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet > /dev/null 2>&1 \
            || hdiutil detach "$MOUNT_POINT" -force -quiet > /dev/null 2>&1 || true
    fi
    find "$WORK_DIR" -delete 2>/dev/null || true
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

section() { printf '\n== %s ==\n' "$1"; }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL %s\n' "$1"; }

check() {
    local description="$1"
    shift
    if "$@" > /dev/null 2>&1; then pass "$description"; else fail "$description"; fi
}

check_contains() {
    local description="$1" needle="$2"
    shift 2
    if "$@" 2>/dev/null | grep -F -- "$needle" > /dev/null; then pass "$description"; else fail "$description"; fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

check_plist() {
    local key="$1" expected="$2" plist="$3" actual
    actual="$(plist_value "$key" "$plist")"
    if [ "$actual" = "$expected" ]; then
        pass "$key = $expected"
    else
        fail "${key}：期望 ${expected}，实际 ${actual:-<空>}"
    fi
}

# Lists every entry with a content hash, to compare the app in the ZIP and the DMG.
tree_fingerprint() {
    (
        cd "$1" || exit 1
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
for name in "$ZIP_NAME" "$DMG_NAME" SHA256SUMS; do
    check "$name 存在且非空" test -s "$DIST_DIR/$name"
done
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "缺少产物文件，无法继续校验。" >&2
    exit 1
fi
if (cd "$DIST_DIR" && shasum -a 256 -c SHA256SUMS > /dev/null 2>&1); then
    pass "SHA256SUMS 全部匹配"
else
    fail "SHA256SUMS 校验失败"
fi

section "ZIP 内容"
ZIP_ROOT="$WORK_DIR/zip"
mkdir -p "$ZIP_ROOT"
check "ZIP 可以解压" ditto -x -k "$ZIP_PATH" "$ZIP_ROOT"
ZIP_APP="$ZIP_ROOT/$APP_NAME.app"
if [ ! -d "$ZIP_APP" ]; then
    fail "ZIP 里没有 $APP_NAME.app"
    printf '\n通过 %s 项，失败 %s 项\n' "$PASS_COUNT" "$FAIL_COUNT" >&2
    exit 1
fi

section "Info.plist"
PLIST="$ZIP_APP/Contents/Info.plist"
check_plist CFBundleIdentifier "$BUNDLE_IDENTIFIER" "$PLIST"
check_plist CFBundleShortVersionString "$VERSION" "$PLIST"
check_plist CFBundleVersion "$BUILD_NUMBER" "$PLIST"
check_plist CFBundleDisplayName "$DISPLAY_NAME" "$PLIST"
check_plist LSMinimumSystemVersion "$MINIMUM_SYSTEM_VERSION" "$PLIST"
check_plist LSUIElement true "$PLIST"
check_plist SUFeedURL "$FEED_URL" "$PLIST"
check_plist SUPublicEDKey "$(sparkle_public_key)" "$PLIST"
check_plist SUEnableAutomaticChecks true "$PLIST"
check_plist SUScheduledCheckInterval 3600 "$PLIST"
check_plist SUAutomaticallyUpdate false "$PLIST"
check_plist SUAllowsAutomaticUpdates false "$PLIST"
check_plist SUEnableSystemProfiling false "$PLIST"
check_plist SUVerifyUpdateBeforeExtraction true "$PLIST"
check_plist SURequireSignedFeed true "$PLIST"
check_plist SUSignedFeedFailureExpirationInterval 0 "$PLIST"

section "可执行文件"
BINARY="$ZIP_APP/Contents/MacOS/$APP_NAME"
check "存在主可执行文件" test -x "$BINARY"
for arch in "${ARCHES[@]}"; do
    check_contains "包含 $arch" "$arch" lipo -archs "$BINARY"
done
check_contains "最低系统 $MINIMUM_SYSTEM_VERSION" "minos $MINIMUM_SYSTEM_VERSION" vtool -show-build "$BINARY"
if otool -l "$BINARY" | grep -q '\.build'; then
    fail "没有指向构建目录的加载路径"
else
    pass "没有指向构建目录的加载路径"
fi
check_contains "链接了 Sparkle.framework" "Sparkle.framework" otool -L "$BINARY"
check_contains "rpath 含 @executable_path/../Frameworks" "@executable_path/../Frameworks" otool -l "$BINARY"
check "应用图标" test -f "$ZIP_APP/Contents/Resources/AppIcon.icns"

section "Sparkle.framework"
FRAMEWORK="$ZIP_APP/Contents/Frameworks/Sparkle.framework"
check "Versions/Current 是符号链接" test -L "$FRAMEWORK/Versions/Current"
check "Sparkle 是符号链接" test -L "$FRAMEWORK/Sparkle"
check "Autoupdate 可执行" test -x "$FRAMEWORK/Versions/B/Autoupdate"
check "Updater.app 可执行" test -x "$FRAMEWORK/Versions/B/Updater.app/Contents/MacOS/Updater"
check "Downloader.xpc" test -d "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
check "Installer.xpc" test -d "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
for arch in "${ARCHES[@]}"; do
    check_contains "Sparkle 包含 $arch" "$arch" lipo -archs "$FRAMEWORK/Versions/B/Sparkle"
done

section "签名"
SIGNED_PARTS=(
    "$ZIP_APP"
    "$FRAMEWORK"
    "$FRAMEWORK/Versions/B/Autoupdate"
    "$FRAMEWORK/Versions/B/Updater.app"
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
)
check "应用签名通过深度校验" codesign --verify --deep --strict "$ZIP_APP"
for part in "${SIGNED_PARTS[@]:1}"; do
    check "签名有效：$(basename "$part")" codesign --verify --strict "$part"
done
# A release must carry the shared certificate: macOS keeps the Accessibility grant
# only while the signing identity stays the same (MoliSpec 007 §7.5.2).
if [ "$REQUIRE_SIGNING_CERTIFICATE" = "1" ]; then
    FINGERPRINT="$(grep -Eo '^[0-9a-f]{40}$' "$SIGNING_CERTIFICATE_FILE" || true)"
    if [ -z "$FINGERPRINT" ]; then
        fail "Config/CodeSigningCertificate.txt 里有证书指纹"
    else
        for part in "${SIGNED_PARTS[@]}"; do
            check_contains "由共用证书签名：$(basename "$part")" \
                "certificate leaf = H\"$FINGERPRINT\"" codesign -d -r- "$part"
        done
    fi
fi

section "DMG"
mkdir -p "$MOUNT_POINT"
if hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" > /dev/null 2>&1; then
    DMG_ATTACHED=1
    pass "DMG 可以挂载"
    DMG_APP="$MOUNT_POINT/$APP_NAME.app"
    check "DMG 里有 $APP_NAME.app" test -d "$DMG_APP"
    if [ "$(readlink "$MOUNT_POINT/Applications" 2>/dev/null)" = "/Applications" ]; then
        pass "DMG 里有指向 /Applications 的链接"
    else
        fail "DMG 里缺少指向 /Applications 的链接"
    fi
    if [ -d "$DMG_APP" ]; then
        if diff <(tree_fingerprint "$ZIP_APP") <(tree_fingerprint "$DMG_APP") > "$WORK_DIR/diff.txt"; then
            pass "ZIP 和 DMG 里的应用完全一致"
        else
            fail "ZIP 和 DMG 里的应用不一致"
            head -n 20 "$WORK_DIR/diff.txt"
        fi
    fi
else
    fail "DMG 可以挂载"
fi

section "结果"
printf '通过 %s 项，失败 %s 项\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "打包校验未通过，已阻止发布。" >&2
    exit 1
fi
echo "打包校验通过。"
