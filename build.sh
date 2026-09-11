#!/bin/bash
# MacCleaner 构建脚本
#
# 关键点：这台机器的默认 SDK 是 MacOSX26.2.sdk，但编译器是 Swift 6.1.2（macOS 15 时代），
# 两者不兼容 —— SwiftUI 的 .swiftinterface 会解析失败。因此必须显式指定 MacOSX15.sdk。
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJ/Sources/MacCleaner"
OUT="$PROJ/build"
APP="$OUT/MacCleaner.app"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"
TARGET="arm64-apple-macosx15.0"

if [ ! -d "$SDK" ]; then
  echo "❌ 找不到 SDK: $SDK"
  echo "   可用 SDK:"; ls -1 /Library/Developer/CommandLineTools/SDKs/
  exit 1
fi

echo "==> 清理"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 收集源文件"
SOURCES=$(find "$SRC" -name '*.swift' | sort)
echo "$SOURCES" | sed 's|^|    |'

echo "==> 编译 ($TARGET)"
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -swift-version 5 \
  -O \
  -parse-as-library \
  -framework SwiftUI -framework AppKit \
  -o "$APP/Contents/MacOS/MacCleaner" \
  $SOURCES

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>MacCleaner</string>
    <key>CFBundleDisplayName</key>       <string>存储清理</string>
    <key>CFBundleIdentifier</key>        <string>com.local.maccleaner</string>
    <key>CFBundleExecutable</key>        <string>MacCleaner</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# ---------- 图标 ----------
ICON="$PROJ/Resources/MacCleaner.icns"
if [ -f "$ICON" ]; then
  echo "==> 安装图标"
  cp "$ICON" "$APP/Contents/Resources/MacCleaner.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string MacCleaner" \
    "$APP/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile MacCleaner" \
    "$APP/Contents/Info.plist"
else
  echo "==> 未找到图标（运行 python3 make_icon.py Resources 生成）"
fi

echo "==> 临时签名 (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/    /' || echo "    (签名跳过，不影响本机运行)"

echo
echo "✅ 构建完成: $APP"
echo "   大小: $(du -sh "$APP" | cut -f1)"
echo "   启动: open \"$APP\""
