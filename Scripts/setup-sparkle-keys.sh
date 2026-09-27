#!/usr/bin/env bash
#
# 一次性生成 Sparkle Ed25519 密钥对。只在开发者本机运行，绝不在 CI 中运行。
#
#   1. generate_keys 生成（或读取已存在的）密钥，私钥保存在登录钥匙串；
#   2. 把公钥写入 Config/SparklePublicKey.txt（可公开、可提交）；
#   3. 把私钥导出到一个新文件，供你复制进 GitHub secret SPARKLE_PRIVATE_KEY。
#
# 私钥是更新信任的唯一凭据：丢失后已发布的版本无法再自动更新，必须离线另行备份。
#
# 用法：Scripts/setup-sparkle-keys.sh <私钥导出路径>
# 环境变量：SPARKLE_TOOLS_DIR（含 bin/generate_keys）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
PUBLIC_KEY_FILE="$ROOT_DIR/Config/SparklePublicKey.txt"
PRIVATE_KEY_OUTPUT="${1:-}"

fail() {
    echo "setup-sparkle-keys.sh: $*" >&2
    exit 1
}

if [ -z "$PRIVATE_KEY_OUTPUT" ]; then
    echo "用法：Scripts/setup-sparkle-keys.sh <私钥导出路径>" >&2
    echo "请传入一个尚不存在的路径，例如：\$HOME/MoliSwitch-sparkle-private-key.txt" >&2
    exit 1
fi

[ -n "$SPARKLE_TOOLS_DIR" ] || fail "缺少 SPARKLE_TOOLS_DIR（Sparkle 工具目录）"

GENERATE_KEYS="$SPARKLE_TOOLS_DIR/bin/generate_keys"
[ -x "$GENERATE_KEYS" ] || fail "找不到可执行的 $GENERATE_KEYS"

if [ -e "$PRIVATE_KEY_OUTPUT" ]; then
    fail "导出路径已存在，请换一个不存在的路径：$PRIVATE_KEY_OUTPUT"
fi

# 不带参数：生成新密钥（或读取已有密钥）并保存到登录钥匙串。
"$GENERATE_KEYS" > /dev/null

PUBLIC_KEY="$("$GENERATE_KEYS" -p | tr -d '[:space:]')"

printf '%s' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$' \
    || fail "公钥格式不正确（应为 32 字节 Ed25519 公钥的 base64）：$PUBLIC_KEY"

mkdir -p "$(dirname "$PUBLIC_KEY_FILE")"

cat > "$PUBLIC_KEY_FILE" <<PUBLIC_KEY_EOF
# Sparkle Ed25519 公钥（44 个字符的 base64，对应 32 字节）。
#
# 由 Scripts/setup-sparkle-keys.sh 生成；可以公开、可以提交。
# 对应私钥只保存在 GitHub Actions secret SPARKLE_PRIVATE_KEY 中，并另行离线备份。
#
# Scripts/build-app.sh 会在缺少公钥时拒绝打包：无法验证更新的安装包不该发布。
$PUBLIC_KEY
PUBLIC_KEY_EOF

"$GENERATE_KEYS" -x "$PRIVATE_KEY_OUTPUT"
chmod 600 "$PRIVATE_KEY_OUTPUT"

cat <<SUMMARY_EOF
公钥已写入：$PUBLIC_KEY_FILE
私钥已导出：$PRIVATE_KEY_OUTPUT

下一步：
  1. 在 GitHub 仓库的 Actions secrets 里新增 SPARKLE_PRIVATE_KEY，内容为该私钥文件全文；
  2. 把私钥文件复制到离线介质备份，然后从本机删除；
  3. 提交 Config/SparklePublicKey.txt。

注意：私钥一旦丢失，已发布的版本将无法再自动更新。
SUMMARY_EOF
