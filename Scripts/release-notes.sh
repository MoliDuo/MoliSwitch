#!/usr/bin/env bash
#
# Prints the release notes for the current tag in the shared template (MoliSpec 006 §6.7),
# from the Conventional Commits since the previous tag.

set -euo pipefail

# shellcheck source=Scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$ROOT_DIR"

previous="$(git describe --tags --abbrev=0 --match 'v*.*.*' "$TAG^" 2>/dev/null || true)"
if [ -z "$previous" ]; then
    # Releases up to 0.2.41 were tagged build-<run>-<attempt>; start after the last of them.
    previous="$(git describe --tags --abbrev=0 --match 'build-*' "$TAG^" 2>/dev/null || true)"
fi
range="${previous:+$previous..}$TAG"

breaking=()
features=()
fixes=()
improvements=()
while IFS= read -r subject; do
    description="${subject#*: }"
    case "$subject" in
        *!:*)
            breaking+=("$description")
            continue
            ;;
    esac
    case "$subject" in
        feat*) features+=("$description") ;;
        fix*) fixes+=("$description") ;;
        perf* | refactor*) improvements+=("$description") ;;
    esac
done < <(git log --format=%s "$range")

echo "## 更新内容"
for line in "${breaking[@]+"${breaking[@]}"}"; do echo "- ⚠️ 需要注意：$line"; done
for line in "${features[@]+"${features[@]}"}"; do echo "- ✨ 新功能：$line"; done
for line in "${fixes[@]+"${fixes[@]}"}"; do echo "- 🐛 修复：$line"; done
for line in "${improvements[@]+"${improvements[@]}"}"; do echo "- ⚡ 优化：$line"; done
if [ $((${#breaking[@]} + ${#features[@]} + ${#fixes[@]} + ${#improvements[@]})) -eq 0 ]; then
    echo "- 内部改进，没有用户可见的变化。"
fi

cat <<NOTES

## 下载
| 平台 | 文件 |
|---|---|
| macOS 14+（Apple 芯片和 Intel） | [$DMG_NAME](https://github.com/$REPOSITORY/releases/download/$TAG/$DMG_NAME) |

## 首次安装
1. 打开 DMG，把 $DISPLAY_NAME 拖进「应用程序」。
2. 应用使用自签名证书，没有经过 Apple 公证：第一次打开时如果被拦下，到「系统设置 › 隐私与安全性」点「仍要打开」。
3. 按提示在「系统设置 › 隐私与安全性 › 辅助功能」里允许 ${DISPLAY_NAME}；按终端标签页切换时，还会请求「自动化」权限。
4. 从 0.2.15 及更早的版本升级：先在「辅助功能」里删掉旧条目，再重新授权一次。

之后的版本会在应用里提示更新，权限保留。

## 校验
对应提交 $(git rev-parse "$TAG^{commit}")；校验和见 SHA256SUMS。
NOTES
