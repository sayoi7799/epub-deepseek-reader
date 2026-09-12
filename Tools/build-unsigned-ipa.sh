#!/bin/bash
# 在任意 macOS 上（包括云 Mac）一条命令构建出未签名的 IPA。
# 用法： bash Tools/build-unsigned-ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."

latest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -n 1 || true)"
if [ -n "$latest" ]; then
  echo "使用 $latest"
  sudo xcode-select -s "$latest/Contents/Developer" 2>/dev/null || true
else
  echo "使用默认 Xcode"
fi
xcodebuild -version

xcodebuild \
  -project EPUBTranslator.xcodeproj \
  -scheme EPUBTranslator \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

app="$(find build/Build/Products/Debug-iphoneos -maxdepth 1 -name '*.app' | head -n 1)"
if [ -z "$app" ]; then
  echo "没有找到 .app，编译可能失败了。"
  exit 1
fi

rm -rf Payload EPUBTranslator-unsigned.ipa
mkdir -p Payload
cp -R "$app" Payload/
zip -qry EPUBTranslator-unsigned.ipa Payload
echo "完成：$(pwd)/EPUBTranslator-unsigned.ipa"
