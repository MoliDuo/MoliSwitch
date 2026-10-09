#!/usr/bin/env bash
#
# Builds .build/MoliSwitch.app:
#   * universal release binary (arm64 + x86_64), version from the VERSION file
#   * Sparkle.framework embedded (symlinks and helpers kept)
#   * Info.plist with the Sparkle keys (MoliSpec 007)
#   * signed (ad-hoc by default, the shared certificate in the release workflow) and verified
#
# Environment:
#   CONFIGURATION  swift build configuration, default release
#   UNIVERSAL      1 (default) builds arm64 + x86_64; 0 builds only this Mac's architecture
#   SIGN_IDENTITY  signing identity, default "-" (ad-hoc); may be a SHA-1 fingerprint
#   SIGN_KEYCHAIN  look the identity up only in this keychain file

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CONFIGURATION="${CONFIGURATION:-release}"
UNIVERSAL="${UNIVERSAL:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"

cd "$ROOT_DIR"

fail() {
    echo "build-app.sh: $*" >&2
    exit 1
}

# An app without the public key can never verify an update.
PUBLIC_KEY="$(sparkle_public_key)"
printf '%s' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$' \
    || fail "Config/SparklePublicKey.txt 里不是 32 字节 Ed25519 公钥的 base64：$PUBLIC_KEY"

# ------------------------------------------------------------------ build --
BINARIES=()
if [ "$UNIVERSAL" = "1" ]; then
    # SwiftPM writes every architecture to the same output directory, so copy each
    # binary out before building the next one.
    STAGING_DIR="$ROOT_DIR/.build/arch-staging"
    remove_path "$STAGING_DIR"
    for arch in "${ARCHES[@]}"; do
        swift build -c "$CONFIGURATION" --product "$APP_NAME" --arch "$arch"
        bin_dir="$(swift build -c "$CONFIGURATION" --arch "$arch" --show-bin-path)"
        [ -f "$bin_dir/$APP_NAME" ] || fail "构建产物不存在：$bin_dir/$APP_NAME"
        mkdir -p "$STAGING_DIR/$arch"
        cp "$bin_dir/$APP_NAME" "$STAGING_DIR/$arch/$APP_NAME"
        BINARIES+=("$STAGING_DIR/$arch/$APP_NAME")
    done
else
    swift build -c "$CONFIGURATION" --product "$APP_NAME"
    bin_dir="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    [ -f "$bin_dir/$APP_NAME" ] || fail "构建产物不存在：$bin_dir/$APP_NAME"
    BINARIES+=("$bin_dir/$APP_NAME")
fi

# Picks a Sparkle.framework with both architectures when building universal.
framework_is_usable() {
    local binary="$1/Versions/Current/Sparkle" archs
    [ -e "$binary" ] || return 1
    [ -e "$1/Versions/Current/Autoupdate" ] || return 1
    [ -e "$1/Versions/Current/Updater.app" ] || return 1
    [ "$UNIVERSAL" = "1" ] || return 0
    archs="$(lipo -archs "$binary" 2>/dev/null || true)"
    [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]
}

SPARKLE_FRAMEWORK=""
while IFS= read -r candidate; do
    if framework_is_usable "$candidate"; then
        SPARKLE_FRAMEWORK="$candidate"
        break
    fi
done < <(find "$ROOT_DIR/.build/artifacts" -maxdepth 6 -type d -name Sparkle.framework 2>/dev/null | sort)
[ -n "$SPARKLE_FRAMEWORK" ] || fail "在 .build/artifacts 下找不到包含所需架构的 Sparkle.framework"
echo "使用 Sparkle.framework：$SPARKLE_FRAMEWORK"

# --------------------------------------------------------------- assemble --
remove_path "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"

BINARY_PATH="$APP_PATH/Contents/MacOS/$APP_NAME"
if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$BINARY_PATH"
else
    lipo -create -output "$BINARY_PATH" "${BINARIES[@]}"
fi
chmod +x "$BINARY_PATH"

# SwiftPM records the link SDK as the minimum system, so newer macOS shows the
# windows with the old look; write the real minimum and the SDK actually used.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos "$MINIMUM_SYSTEM_VERSION" "$SDK_VERSION" -replace \
    -output "$BINARY_PATH" "$BINARY_PATH"

if [ "$UNIVERSAL" = "1" ]; then
    built_archs="$(lipo -archs "$BINARY_PATH")"
    [[ "$built_archs" == *arm64* && "$built_archs" == *x86_64* ]] \
        || fail "可执行文件不是通用二进制：$built_archs"
fi

# The icon comes from the design system (MoliSpec/design/dist/icons/switch), copied unchanged.
cp "$ROOT_DIR/Config/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
ditto "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/Sparkle.framework"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>读取终端当前标签页，用来按前台程序切换输入法</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 XIANGYU MOU</string>
    <key>SUFeedURL</key>
    <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>3600</integer>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
    <key>SUEnableSystemProfiling</key>
    <false/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUSignedFeedFailureExpirationInterval</key>
    <integer>0</integer>
</dict>
</plist>
PLIST_EOF
plutil -lint "$APP_PATH/Contents/Info.plist" > /dev/null || fail "Info.plist 格式错误"

# ------------------------------------------------------------------ rpath --
rpath_list() {
    otool -l "$1" | awk '/cmd LC_RPATH/{f=1} f && $1=="path"{print $2; f=0}'
}

# No load path may point into the build directory.
while IFS= read -r rpath; do
    case "$rpath" in
        *.build/*)
            install_name_tool -delete_rpath "$rpath" "$BINARY_PATH"
            ;;
    esac
done < <(rpath_list "$BINARY_PATH")

if ! rpath_list "$BINARY_PATH" | grep -qx '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$BINARY_PATH"
fi
otool -L "$BINARY_PATH" | grep -q 'Sparkle.framework' || fail "可执行文件没有链接 Sparkle.framework"

# ---------------------------------------------------------------- signing --
xattr -cr "$APP_PATH" 2>/dev/null || true

SIGN_ARGUMENTS=(--force --sign "$SIGN_IDENTITY")
if [ -n "$SIGN_KEYCHAIN" ]; then
    SIGN_ARGUMENTS+=(--keychain "$SIGN_KEYCHAIN")
fi

sign_path() {
    codesign "${SIGN_ARGUMENTS[@]}" "$1"
}

FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_VERSION_PATH="$FRAMEWORK_PATH/Versions/B"
for xpc in "$FRAMEWORK_VERSION_PATH"/XPCServices/*.xpc; do
    [ -e "$xpc" ] && sign_path "$xpc"
done
sign_path "$FRAMEWORK_VERSION_PATH/Updater.app"
sign_path "$FRAMEWORK_VERSION_PATH/Autoupdate"
sign_path "$FRAMEWORK_PATH"
sign_path "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH" || fail "签名校验失败"

echo "已构建 ${APP_PATH}（版本 ${VERSION}，构建号 ${BUILD_NUMBER}）"
