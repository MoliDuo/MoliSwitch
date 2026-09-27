#!/usr/bin/env bash
#
# 一次性生成自签名代码签名证书。只在开发者本机运行，绝不在 CI 中运行。
#
# ad-hoc 签名的应用每个版本的签名都不同，系统（辅助功能、自动化权限）会把更新后的
# 版本当成新应用，要求重新授权。用同一张证书签名后，指定要求（designated
# requirement）变成“Bundle ID + 证书”，跨版本不变，授权得以保留。
#
# 自签名证书不被 Gatekeeper 信任，首次安装仍需“仍要打开”；它只解决授权保留问题。
#
#   1. 生成 RSA 私钥与 10 年有效的代码签名证书；
#   2. 打包为 .p12（随机口令）写入指定目录，口令写入同目录的 .password 文件；
#   3. 把证书 SHA-1 指纹写入 Config/CodeSigningCertificate.txt（可公开、可提交），
#      发布校验用它确认正式版确实由这张证书签名。
#
# 然后把 .p12 的 base64 与口令分别存入 GitHub secrets CODESIGN_P12_BASE64 和
# CODESIGN_P12_PASSWORD，并离线备份 .p12 与口令。
#
# 用法：Scripts/setup-signing-certificate.sh <导出目录>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINGERPRINT_FILE="$ROOT_DIR/Config/CodeSigningCertificate.txt"
OUTPUT_DIR="${1:-}"
COMMON_NAME="AutoInputSwitcher Self-Signed Code Signing"
# 系统自带的 LibreSSL 导出的 .p12 能被 security import 直接读取。
OPENSSL=/usr/bin/openssl

fail() {
    echo "setup-signing-certificate.sh: $*" >&2
    exit 1
}

if [ -z "$OUTPUT_DIR" ]; then
    echo "用法：Scripts/setup-signing-certificate.sh <导出目录>" >&2
    echo "请传入一个尚不存在的目录，例如：\$HOME/AutoInputSwitcher-codesign" >&2
    exit 1
fi

if [ -e "$OUTPUT_DIR" ]; then
    fail "导出目录已存在，请换一个不存在的路径：$OUTPUT_DIR"
fi

umask 077
mkdir -p "$OUTPUT_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/cert.cnf" <<CONFIG_EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $COMMON_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG_EOF

"$OPENSSL" req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK_DIR/cert.cnf" \
    -keyout "$WORK_DIR/key.pem" \
    -out "$WORK_DIR/cert.pem" 2> /dev/null \
    || fail "生成证书失败"

PASSWORD="$("$OPENSSL" rand -hex 24)"

"$OPENSSL" pkcs12 -export \
    -inkey "$WORK_DIR/key.pem" \
    -in "$WORK_DIR/cert.pem" \
    -name "$COMMON_NAME" \
    -passout "pass:$PASSWORD" \
    -out "$OUTPUT_DIR/AutoInputSwitcher-codesign.p12" \
    || fail "导出 .p12 失败"

printf '%s\n' "$PASSWORD" > "$OUTPUT_DIR/AutoInputSwitcher-codesign.password"

FINGERPRINT="$("$OPENSSL" x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
printf '%s' "$FINGERPRINT" | grep -Eq '^[0-9a-f]{40}$' || fail "证书指纹格式不正确：$FINGERPRINT"

cat > "$FINGERPRINT_FILE" <<FINGERPRINT_EOF
# 正式版代码签名证书的 SHA-1 指纹（自签名，CN=$COMMON_NAME）。
#
# 由 Scripts/setup-signing-certificate.sh 生成；可以公开、可以提交。
# 对应的 .p12 只保存在 GitHub Actions secrets CODESIGN_P12_BASE64 / CODESIGN_P12_PASSWORD 中，
# 并另行离线备份。换证书会让所有用户重新授权一次辅助功能与自动化权限。
#
# Scripts/verify-package.sh 在 REQUIRE_SIGNING_CERTIFICATE=1 时要求应用由这张证书签名。
$FINGERPRINT
FINGERPRINT_EOF

echo "已生成："
echo "  $OUTPUT_DIR/AutoInputSwitcher-codesign.p12"
echo "  $OUTPUT_DIR/AutoInputSwitcher-codesign.password"
echo "  $FINGERPRINT_FILE（指纹 $FINGERPRINT）"
