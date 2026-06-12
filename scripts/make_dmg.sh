#!/bin/bash
# 把已构建的 KeyFiesta.app 打包成可拖拽安装的 DMG。
# 用法：先 ./scripts/build.sh，再 ./scripts/make_dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/KeyFiesta.app
DMG=dist/KeyFiesta.dmg
[ -d "$APP" ] || { echo "找不到 $APP，请先运行 ./scripts/build.sh"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"          # 拖拽安装目标

rm -f "$DMG"
hdiutil create -volname "KeyFiesta $VERSION" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "DMG OK: $DMG ($(du -h "$DMG" | cut -f1))"
