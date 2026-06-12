#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 单元测试 =="
swiftc -swift-version 5 -parse-as-library \
  Sources/KeyFiesta/BurstThrottle.swift Sources/KeyFiesta/SoundPicker.swift \
  Sources/KeyFiesta/Geometry.swift Sources/KeyFiesta/Settings.swift \
  Tests/run_tests.swift -o /tmp/kf_build_tests
/tmp/kf_build_tests

APP=dist/KeyFiesta.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/KeyFiesta/*.swift \
  -o "$APP/Contents/MacOS/KeyFiesta"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"

# 优先用固定自签名身份（designated requirement 基于证书哈希，跨重建稳定，
# 辅助功能授权一次后永久保留）；未安装该证书的机器回退 ad-hoc。
#
# 一次性创建该证书（仅本机开发用，可选）：
#   openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
#     -keyout /tmp/kf_key.pem -out /tmp/kf_cert.pem \
#     -subj "/CN=KeyFiesta Local Signer" \
#     -addext "basicConstraints=critical,CA:false" \
#     -addext "keyUsage=critical,digitalSignature" \
#     -addext "extendedKeyUsage=critical,codeSigning"
#   openssl pkcs12 -export -out /tmp/kf.p12 -inkey /tmp/kf_key.pem -in /tmp/kf_cert.pem \
#     -passout pass:kflocal -name "KeyFiesta Local Signer" \
#     -legacy -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
#   security import /tmp/kf.p12 -k ~/Library/Keychains/login.keychain-db \
#     -P kflocal -T /usr/bin/codesign -A
IDENTITY="KeyFiesta Local Signer"
if security find-identity -v 2>/dev/null | grep -q "$IDENTITY" \
   || security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  SIGN_ID="$IDENTITY"
  echo "签名身份: $IDENTITY（固定，授权可持久）"
else
  SIGN_ID="-"
  echo "签名身份: ad-hoc（未找到固定证书，重建后需重新授权）"
fi
codesign --force -s "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" dist/KeyFiesta.zip

echo "BUILD OK: $APP"
