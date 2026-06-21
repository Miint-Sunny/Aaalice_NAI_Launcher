#!/usr/bin/env bash
# macOS 一键打包 DMG：release 构建 + 自签名证书重签 + create-dmg 打包。
#
# 依赖：
#   - Flutter / Xcode / CocoaPods（构建；pod install 需 UTF-8，脚本已设 LANG）
#   - git-lfs：assets/databases/*.db 是 LFS，构建前需 `git lfs pull`
#   - create-dmg：`brew install create-dmg`
#   - 本地签名证书 "NAI Launcher Local Dev"（用 scripts/create_macos_dev_cert.sh 创建）
#
# 用法：scripts/build_dmg.sh
# 产物：build/Aaalice_NAI_Launcher.dmg（内含 Aaalice NAI Launcher.app）
#
# 注意：自签名未公证，下载者首次打开需去隔离：
#   xattr -dr com.apple.quarantine "/Applications/Aaalice NAI Launcher.app"
set -euo pipefail
cd "$(dirname "$0")/.."
export LANG="${LANG:-en_US.UTF-8}"

IDENTITY="${SIGN_IDENTITY:-NAI Launcher Local Dev}"
KC="$HOME/Library/Keychains/nai-codesign.keychain-db"
KC_PASS="${SIGN_KEYCHAIN_PASS:-naidev}"
APP="build/macos/Build/Products/Release/Aaalice NAI Launcher.app"
DMG="build/Aaalice_NAI_Launcher.dmg"        # 文件名用下划线（点号在某些工具下有坑）
VOLNAME="Aaalice NAI Launcher"

command -v create-dmg >/dev/null 2>&1 || { echo "[ERROR] 缺 create-dmg：brew install create-dmg"; exit 1; }
security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
  || { echo "[ERROR] 找不到签名证书 '$IDENTITY'：先跑 scripts/create_macos_dev_cert.sh"; exit 1; }

echo "[1/3] flutter build macos --release ..."
pkill -f "Aaalice NAI Launcher.app/Contents/MacOS" 2>/dev/null || true
flutter build macos --release

echo "[2/3] 用 '$IDENTITY' 重签（先非交互解锁签名钥匙串，避免 errSecInternalComponent）..."
security unlock-keychain -p "$KC_PASS" "$KC"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null 2>&1 || true
codesign --force --deep --sign "$IDENTITY" --keychain "$KC" \
  --entitlements macos/Runner/Release.entitlements "$APP"
codesign --verify --verbose=2 "$APP"

echo "[3/3] create-dmg 打包 ..."
rm -f "$DMG"
create-dmg \
  --volname "$VOLNAME" \
  --window-pos 200 120 \
  --window-size 640 400 \
  --icon-size 110 \
  --icon "Aaalice NAI Launcher.app" 160 200 \
  --app-drop-link 480 200 \
  --no-internet-enable \
  "$DMG" \
  "$APP"

echo
echo "✅ 完成：$DMG"
echo "发版示例："
echo "  gh release create <tag> --repo <owner>/<repo> \\"
echo "    --title 'Aaalice NAI Launcher · macOS · <ver>' --notes-file <notes.md> \\"
echo "    \"$DMG\""
