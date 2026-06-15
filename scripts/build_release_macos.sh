#!/usr/bin/env bash
set -euo pipefail

# ========================================
#   NAI Launcher macOS Release Build
#   对标 scripts/build_release.bat（Windows）
# ========================================

# 切换到项目根目录
cd "$(dirname "$0")/.."

# CocoaPods 需要 UTF-8 终端编码
export LANG="${LANG:-en_US.UTF-8}"

APP_PATH="build/macos/Build/Products/Release/Aaalice NAI Launcher.app"

echo "========================================"
echo "  NAI Launcher macOS Release Build"
echo "========================================"
echo

echo "[0/3] 准备预构建数据库（Git LFS）..."
if command -v git-lfs >/dev/null 2>&1; then
  git lfs pull --include="assets/databases/*.db" || echo "[WARN] git lfs pull 失败，继续构建（数据库功能可能不可用）"
else
  echo "[WARN] 未检测到 git-lfs。assets/databases/*.db 可能仍是 LFS 占位文件，"
  echo "       翻译/标签等数据库功能将不可用。请先安装：brew install git-lfs && git lfs install"
fi
echo

echo "[1/3] 生成本地化文件..."
flutter gen-l10n || true
# 若拉取/修改了带注解的源码，需要重新生成 freezed/json/riverpod 代码，取消下一行注释：
# dart run build_runner build --delete-conflicting-outputs
echo

echo "[2/3] 构建 Release 版本（首次会自动执行 pod install）..."
flutter build macos --release
echo

echo "[3/3] 代码签名（可选）..."
# 默认使用 Flutter 的本地 ad-hoc 签名，可直接在本机运行。
# 如需用 Apple Developer ID 签名并公证以分发给其他用户，取消注释并填入证书：
# CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# codesign --deep --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP_PATH"
# xcrun notarytool submit "$APP_PATH" --keychain-profile "AC_PASSWORD" --wait
echo "[INFO] 使用本地 ad-hoc 签名（如需正式分发请配置 Developer ID，见脚本注释）"
echo

echo "========================================"
echo "  构建完成！"
echo "  产物: $APP_PATH"
echo "========================================"
