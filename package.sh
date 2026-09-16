#!/bin/bash
# MacCleaner 打包脚本 —— 生成可分发的 .dmg 安装包
#
# 产出:
#   build/MacCleaner.app        通用二进制 (arm64 + x86_64)
#   build/MacCleaner-<VERSION>.dmg  安装镜像（双击挂载 → 拖入 Applications）
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJ/Sources/MacCleaner"
OUT="$PROJ/build"
APP="$OUT/MacCleaner.app"
STAGE="$OUT/dmg-stage"
VERSION="1.2.1"                      # 发布版本号，改这里即可
BUILD_NUM="4"                      # CFBundleVersion，每次发布 +1
DMG="$OUT/MacCleaner-$VERSION.dmg"
VOLNAME="MacCleaner 安装"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk"

if [ ! -d "$SDK" ]; then
  echo "❌ 找不到 SDK: $SDK"; exit 1
fi

echo "==> 清理旧产物"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=$(find "$SRC" -name '*.swift' | sort)

# ---------- 1. 编译通用二进制 ----------
compile_arch() {
  local arch="$1" label="$2"
  echo "    编译 $label …"
  swiftc \
    -sdk "$SDK" \
    -target "${arch}-apple-macosx15.0" \
    -swift-version 5 -O -parse-as-library \
    -framework SwiftUI -framework AppKit \
    -o "$OUT/MacCleaner-$arch" \
    $SOURCES
}

echo "==> 编译 (universal: arm64 + x86_64)"
compile_arch arm64   "arm64 (Apple Silicon)"
compile_arch x86_64  "x86_64 (Intel)"

echo "==> 合并为通用二进制"
lipo -create -output "$APP/Contents/MacOS/MacCleaner" \
  "$OUT/MacCleaner-arm64" "$OUT/MacCleaner-x86_64"
rm -f "$OUT/MacCleaner-arm64" "$OUT/MacCleaner-x86_64"
lipo -info "$APP/Contents/MacOS/MacCleaner" | sed 's/^/    /'

# ---------- 2. Info.plist ----------
echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>MacCleaner</string>
    <key>CFBundleDisplayName</key>       <string>存储清理</string>
    <key>CFBundleIdentifier</key>        <string>com.local.maccleaner</string>
    <key>CFBundleExecutable</key>        <string>MacCleaner</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
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

# ---------- 3. 签名 ----------
echo "==> Ad-hoc 签名"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/    /' || true
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /' || true

# ---------- 4. 组装 DMG 内容 ----------
echo "==> 组装安装镜像"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 附带一个说明文件，方便首次打开
cat > "$STAGE/安装说明.txt" <<'TXT'
MacCleaner —— macOS 存储查看与清理工具
========================================

安装：
  把左边的 MacCleaner 拖到右边的 Applications 文件夹。

首次打开如果提示「无法验证开发者」：
  在「应用程序」里右键点击 MacCleaner → 选「打开」→ 再点「打开」。
  只需做一次，之后双击即可正常打开。

也可以运行这条命令绕过检查：
  xattr -d com.apple.quarantine /Applications/MacCleaner.app

使用：
  左侧边栏切换功能，分三组共 8 个页面。

  存储
    清理      扫描缓存、日志与开发残留，勾选后清理
    空间      矩形树图看「空间去哪了」，单击钻取、双击在访达中显示
    重复文件  按内容哈希找出完全相同的文件
  系统
    内存      实时内存分布与占用最高的进程（只读，不会结束任何进程）
  工具
    应用卸载  删除应用本体，并一并清理它在 ~/Library 里的残留
    卸载残余  找出已删除应用留下的无主文件
    清理历史  累计释放量与趋势
    磁盘健康  文件系统 / APFS 容器 / 快照 / SMART 状态

所有清理都会移入废纸篓，可随时恢复。

本工具只会清理缓存、日志等可重建内容。
你的文档、照片、密钥链等个人数据受白名单机制保护，不会被触碰。
TXT

# ---------- 5. 生成 DMG ----------
echo "==> 生成 DMG"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -fs HFS+ \
  "$DMG" 2>&1 | tail -3 | sed 's/^/    /'

rm -rf "$STAGE"

# ---------- 6. 校验 ----------
echo
echo "==> 校验镜像"
hdiutil verify "$DMG" 2>&1 | tail -2 | sed 's/^/    /'

echo
echo "✅ 打包完成"
echo "   APP: $(du -sh "$APP" | cut -f1)   $APP"
echo "   DMG: $(du -sh "$DMG" | cut -f1)   $DMG"
echo
echo "   安装: open \"$DMG\""
