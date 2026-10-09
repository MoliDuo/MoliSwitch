#!/usr/bin/env bash
#
# The check entry (MoliSpec 004 §4.2.1), run the same way locally and in CI:
# format check, lint, build, the Core checks, unit tests.
#
# SwiftFormat and SwiftLint are downloaded once into .build/tools at pinned
# versions and verified against their checksums.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TOOLS_DIR="$ROOT_DIR/.build/tools"

SWIFTFORMAT_VERSION="0.63.1"
SWIFTFORMAT_SHA256="385ef1a263ba28685157b98c5536b9c9105e124518f28b7ef8a2bee4b167eaeb"
SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

# fetch_tool <name> <version> <url> <sha256> <binary inside the zip>
fetch_tool() {
    local name="$1" version="$2" url="$3" sha="$4" inner="$5"
    local dir="$TOOLS_DIR/$name-$version"
    if [ -x "$dir/$name" ]; then
        return
    fi
    echo "下载 $name $version"
    mkdir -p "$dir"
    local archive="$dir/download.zip"
    curl -fsSL --retry 3 -o "$archive" "$url"
    echo "$sha  $archive" | shasum -a 256 -c - > /dev/null
    ditto -x -k "$archive" "$dir/unpacked"
    mv "$dir/unpacked/$inner" "$dir/$name"
    chmod +x "$dir/$name"
    find "$archive" "$dir/unpacked" -delete
}

fetch_tool swiftformat "$SWIFTFORMAT_VERSION" \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" \
    "$SWIFTFORMAT_SHA256" swiftformat
fetch_tool swiftlint "$SWIFTLINT_VERSION" \
    "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
    "$SWIFTLINT_SHA256" swiftlint

SWIFTFORMAT="$TOOLS_DIR/swiftformat-$SWIFTFORMAT_VERSION/swiftformat"
SWIFTLINT="$TOOLS_DIR/swiftlint-$SWIFTLINT_VERSION/swiftlint"

if [ "${1:-}" = "--fix" ]; then
    "$SWIFTFORMAT" .
    "$SWIFTLINT" --fix --quiet
    exit 0
fi

echo "== 格式 =="
"$SWIFTFORMAT" --lint .

echo "== Lint =="
"$SWIFTLINT" lint --strict --quiet

echo "== 编译 =="
swift build --build-tests -Xswiftc -warnings-as-errors

echo "== Core 检查 =="
swift run MoliSwitchCoreChecks

echo "== 单元测试 =="
swift test --skip-build

echo "全部检查通过。"
