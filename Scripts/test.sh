#!/usr/bin/env bash
#
# MoliSwitch 完整校验：核心检查、单元测试、打包、产物校验。
# 任何一步失败都以非零状态退出，CI 用同一个脚本作为发布前的阻断检查。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_LOG="$ROOT_DIR/.build/test-package.log"
mkdir -p "$ROOT_DIR/.build"

echo "== 核心检查 =="
swift run MoliSwitchCoreChecks

echo "== 单元测试 =="
swift test

echo "== 打包 =="
if ! "$ROOT_DIR/Scripts/package-release.sh" > "$PACKAGE_LOG" 2>&1; then
    echo "package-release.sh 失败，完整日志：" >&2
    cat "$PACKAGE_LOG" >&2
    exit 1
fi
cat "$PACKAGE_LOG"

echo "== 产物校验 =="
"$ROOT_DIR/Scripts/verify-package.sh"

echo "全部校验通过。"
