# Build & Release

本文档记录如何构建可分发的 boringNotchVibe DMG。

## 前置条件

- Xcode 已安装
- 无需 Apple Developer 账号（使用 ad-hoc 签名）

## 构建步骤

### 1. Release 构建

```bash
xcodebuild -scheme boringNotch -configuration Release \
  -derivedDataPath /tmp/boringNotch-build build
```

产物位于 `/tmp/boringNotch-build/Build/Products/Release/boringNotch.app`。

### 2. 递归重签名

由于 `MediaRemoteAdapter.framework` 等内嵌 framework 使用了其他 Team ID，xcodebuild ad-hoc 构建不会自动重签，必须手动递归重签，否则 dyld 启动时报 `code signature not valid` 并崩溃。

```bash
APP="/tmp/boringNotch-build/Build/Products/Release/boringNotch.app"

# 先签所有内嵌 framework / dylib
find "$APP/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) | while read f; do
    codesign --force --sign - --timestamp=none "$f"
done

# 再签整个 app bundle
codesign --force --sign - --timestamp=none "$APP"
```

### 3. 打包为 DMG

```bash
VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)
STAGING="/tmp/boringNotchVibe-staging"
DMG_OUT="$HOME/Desktop/boringNotchVibe-${VERSION}.dmg"

rm -rf "$STAGING" && mkdir "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 写入 Install Helper.command（双击移除 Gatekeeper 隔离）
cat > "$STAGING/Install Helper.command" << 'EOF'
#!/bin/bash
APP="/Applications/boringNotch.app"
if [ ! -d "$APP" ]; then
  echo "未找到 $APP，请先将 boringNotch.app 拖入 Applications 文件夹。"
  read -p "按 Enter 退出..."
  exit 1
fi
xattr -cr "$APP"
echo "✅ 完成！可以双击启动 boringNotch 了。"
read -p "按 Enter 退出..."
EOF
chmod +x "$STAGING/Install Helper.command"

hdiutil create \
  -volname "boringNotchVibe" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_OUT"

rm -rf "$STAGING"
```

### 4. 清理构建产物

```bash
rm -rf /tmp/boringNotch-build
```

## 用户安装说明

1. 打开 DMG，将 `boringNotch.app` 拖入 Applications
2. 双击 DMG 内的 **`Install Helper.command`**，Terminal 会自动移除 Gatekeeper 隔离
3. 双击启动即可

> **为什么需要这一步？** 应用使用 ad-hoc 签名（无 Apple Developer 账号），macOS Gatekeeper 会隔离从网络下载的未公证应用。`Install Helper.command` 内部执行 `xattr -cr` 移除隔离属性。

## 一键构建脚本

以上步骤合并为单条命令序列：

```bash
APP_BUILD="/tmp/boringNotch-build/Build/Products/Release/boringNotch.app"

xcodebuild -scheme boringNotch -configuration Release \
  -derivedDataPath /tmp/boringNotch-build build && \

find "$APP_BUILD/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) \
  | while read f; do codesign --force --sign - --timestamp=none "$f"; done && \
codesign --force --sign - --timestamp=none "$APP_BUILD" && \

VERSION=$(defaults read "$APP_BUILD/Contents/Info.plist" CFBundleShortVersionString) && \
STAGING="/tmp/boringNotchVibe-staging" && \
rm -rf "$STAGING" && mkdir "$STAGING" && \
cp -R "$APP_BUILD" "$STAGING/" && \
ln -s /Applications "$STAGING/Applications" && \
cat > "$STAGING/Install Helper.command" << 'HELPER'
#!/bin/bash
APP="/Applications/boringNotch.app"
if [ ! -d "$APP" ]; then
  echo "未找到 $APP，请先将 boringNotch.app 拖入 Applications 文件夹。"
  read -p "按 Enter 退出..."
  exit 1
fi
xattr -cr "$APP"
echo "✅ 完成！可以双击启动 boringNotch 了。"
read -p "按 Enter 退出..."
HELPER
chmod +x "$STAGING/Install Helper.command" && \
hdiutil create \
  -volname "boringNotchVibe" \
  -srcfolder "$STAGING" \
  -ov -format UDZO -imagekey zlib-level=9 \
  "$HOME/Desktop/boringNotchVibe-${VERSION}.dmg" && \
rm -rf "$STAGING" /tmp/boringNotch-build && \
echo "✅ 完成：$HOME/Desktop/boringNotchVibe-${VERSION}.dmg"
```
