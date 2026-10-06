#!/usr/bin/env bash
#
# 构建 MoliSwitch.app：
#   * 通用二进制（arm64 + x86_64）
#   * 内嵌 Sparkle.framework（保留符号链接与辅助进程）
#   * 写入自动更新所需的 Info.plist 键
#   * 签名（默认 ad-hoc，发布时用固定证书）并校验
#
# 可用环境变量：
#   VERSION       CFBundleShortVersionString，默认 0.2.0
#   BUILD_NUMBER  CFBundleVersion，默认 1
#   CONFIGURATION Swift 构建配置，默认 release
#   UNIVERSAL     1（默认）构建 arm64 + x86_64；0 只构建本机架构
#   SIGN_IDENTITY 签名身份，默认 "-"（ad-hoc）；也可以是证书 SHA-1 指纹
#   SIGN_KEYCHAIN 只在这个钥匙串文件里查找签名身份，默认不限
#   FEED_URL      appcast 地址，默认仓库 Releases 的 latest/download/appcast.xml

set -euo pipefail

APP_NAME="MoliSwitch"
BUNDLE_IDENTIFIER="com.moli.MoliSwitch"
MINIMUM_SYSTEM_VERSION="14.0"
DEFAULT_FEED_URL="https://github.com/MoliDuo/MoliSwitch/releases/latest/download/appcast.xml"

CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UNIVERSAL="${UNIVERSAL:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
FEED_URL="${FEED_URL:-$DEFAULT_FEED_URL}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/$APP_NAME.app"
PUBLIC_KEY_FILE="$ROOT_DIR/Config/SparklePublicKey.txt"

cd "$ROOT_DIR"

fail() {
    echo "build-app.sh: $*" >&2
    exit 1
}

# 递归删除文件或目录，不依赖 rm。
remove_path() {
    local path="$1"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    find "$path" -delete
}

# --------------------------------------------------------------- 公钥校验 --
# 没有公钥的安装包无法验证更新签名，发布出去只会让用户永远停在无法更新的版本。

[ -f "$PUBLIC_KEY_FILE" ] || fail "缺少 $PUBLIC_KEY_FILE"

PUBLIC_KEY="$(sed -e 's/#.*$//' "$PUBLIC_KEY_FILE" | tr -d '[:space:]' | head -n 1)"

case "$PUBLIC_KEY" in
    "" | REPLACE*)
        fail "Config/SparklePublicKey.txt 仍是占位公钥；请先按 README 的\"Sparkle 密钥\"章节写入组织共用的公钥。"
        ;;
esac

if ! printf '%s' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
    fail "公钥不是 32 字节 Ed25519 公钥的 base64（应为 44 个字符）：$PUBLIC_KEY"
fi

# ------------------------------------------------------------------ 构建 --
ARCHES=()
if [ "$UNIVERSAL" = "1" ]; then
    ARCHES=(arm64 x86_64)
fi

BINARIES=()

if [ "${#ARCHES[@]}" -eq 0 ]; then
    swift build -c "$CONFIGURATION" --product "$APP_NAME"
    bin_dir="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    BINARIES+=("$bin_dir/$APP_NAME")
else
    # 较新的 SwiftPM 对不同架构使用同一个输出目录，后一次构建会覆盖前一次，
    # 所以每个架构构建完立即复制到各自的暂存目录。
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
fi

for binary in "${BINARIES[@]}"; do
    [ -f "$binary" ] || fail "构建产物不存在：$binary"
done

# --------------------------------------------------- 定位 Sparkle.framework --
framework_binary() {
    local framework="$1"

    if [ -e "$framework/Versions/Current/Sparkle" ]; then
        printf '%s\n' "$framework/Versions/Current/Sparkle"
    elif [ -e "$framework/Sparkle" ]; then
        printf '%s\n' "$framework/Sparkle"
    fi
}

framework_is_usable() {
    local framework="$1"
    local binary
    local archs

    binary="$(framework_binary "$framework")"
    [ -n "$binary" ] || return 1

    archs="$(lipo -archs "$binary" 2>/dev/null || true)"
    [ -n "$archs" ] || return 1

    if [ "$UNIVERSAL" = "1" ]; then
        case "$archs" in
            *arm64*x86_64* | *x86_64*arm64*) ;;
            *) return 1 ;;
        esac
    fi

    [ -e "$framework/Versions/Current/Autoupdate" ] || return 1
    [ -e "$framework/Versions/Current/Updater.app" ] || return 1

    return 0
}

SPARKLE_FRAMEWORK=""
if [ -d "$ROOT_DIR/.build/artifacts" ]; then
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if framework_is_usable "$candidate"; then
            SPARKLE_FRAMEWORK="$candidate"
            break
        fi
    done < <(find "$ROOT_DIR/.build/artifacts" -maxdepth 6 -type d -name Sparkle.framework 2>/dev/null | sort)
fi

[ -n "$SPARKLE_FRAMEWORK" ] || fail "在 .build/artifacts 下找不到包含所需架构的 Sparkle.framework；请先执行一次 swift build 让依赖完成解析。"

echo "使用 Sparkle.framework：$SPARKLE_FRAMEWORK"

# ------------------------------------------------------------ 组装 bundle --
remove_path "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP_PATH/Contents/MacOS/$APP_NAME"
else
    lipo -create -output "$APP_PATH/Contents/MacOS/$APP_NAME" "${BINARIES[@]}"
fi

chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# SwiftPM 把链接时的 SDK 版本记成最低系统版本，新系统因此按旧版外观显示窗口
# （macOS 27 上侧边栏旁的工具栏背景还会错位）。改记成实际使用的 SDK 版本。
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos "$MINIMUM_SYSTEM_VERSION" "$SDK_VERSION" -replace \
    -output "$APP_PATH/Contents/MacOS/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"

if [ "$UNIVERSAL" = "1" ]; then
    built_archs="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
    case "$built_archs" in
        *arm64*x86_64* | *x86_64*arm64*) ;;
        *) fail "可执行文件不是通用二进制：$built_archs" ;;
    esac
fi

swift "$ROOT_DIR/Scripts/generate-app-icon.swift" "$APP_PATH/Contents/Resources/AppIcon.icns"

ditto "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/Sparkle.framework"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_SYSTEM_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>读取终端当前标签页，用来按前台程序切换输入法</string>
    <key>NSHighResolutionCapable</key>
    <true/>
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

# -------------------------------------------------- 运行路径（rpath）调整 --
BINARY_PATH="$APP_PATH/Contents/MacOS/$APP_NAME"
FRAMEWORK_PATH="$APP_PATH/Contents/Frameworks/Sparkle.framework"

if [ -d "$FRAMEWORK_PATH/Versions/B" ]; then
    FRAMEWORK_VERSION_PATH="$FRAMEWORK_PATH/Versions/B"
else
    FRAMEWORK_VERSION_PATH="$FRAMEWORK_PATH/Versions/Current"
fi

rpath_list() {
    otool -l "$1" | awk '/cmd LC_RPATH/{f=1} f && $1=="path"{print $2; f=0}'
}

# bundle 内不允许存在指向构建目录的绝对加载路径。
while IFS= read -r rpath; do
    [ -n "$rpath" ] || continue
    case "$rpath" in
        *.build/*)
            echo "移除构建目录 rpath：$rpath"
            install_name_tool -delete_rpath "$rpath" "$BINARY_PATH"
            ;;
    esac
done < <(rpath_list "$BINARY_PATH")

if ! rpath_list "$BINARY_PATH" | grep -x '@executable_path/../Frameworks' > /dev/null; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$BINARY_PATH"
fi

otool -L "$BINARY_PATH" | grep 'Sparkle.framework' > /dev/null \
    || fail "可执行文件没有链接 Sparkle.framework"

# ------------------------------------------------------------------- 签名 --
xattr -cr "$APP_PATH" 2>/dev/null || true

SIGN_ARGUMENTS=(--force --sign "$SIGN_IDENTITY")
if [ -n "$SIGN_KEYCHAIN" ]; then
    SIGN_ARGUMENTS+=(--keychain "$SIGN_KEYCHAIN")
fi

sign_path() {
    echo "签名 $(basename "$1")"
    codesign "${SIGN_ARGUMENTS[@]}" "$1"
}

for xpc in "$FRAMEWORK_VERSION_PATH"/XPCServices/*.xpc; do
    [ -e "$xpc" ] || continue
    sign_path "$xpc"
done

sign_path "$FRAMEWORK_VERSION_PATH/Updater.app"
sign_path "$FRAMEWORK_VERSION_PATH/Autoupdate"
sign_path "$FRAMEWORK_PATH"
sign_path "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH" || fail "签名校验失败"

echo "已构建 ${APP_PATH}（版本 ${VERSION}，构建号 ${BUILD_NUMBER}）"
