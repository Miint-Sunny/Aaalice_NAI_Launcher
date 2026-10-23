#!/bin/bash
# 构建 macOS 版，并把 NAI Agent 运行时（Node + Pi）和桥接客户端放进应用包。
#
# 用法：
#   scripts/build_macos.sh [--release]       构建（默认 debug），产物在 build/macos/Build/Products/<Debug|Release>/
#   scripts/build_macos.sh tools <应用包>     只往已有的应用包里放运行时和桥接客户端（例如 flutter run 之后）
#
# - Flutter：用 tool/flutter-sdk.json 登记的版本；FLUTTER_ROOT 指向那份 SDK 时用它，否则用 PATH 上的 flutter
# - Xcode：DEVELOPER_DIR 默认 /Applications/Xcode.app，不改系统的 xcode-select
# - Node：和 Windows 包同一个版本（scripts/prepare_windows_node_runtime.ps1），用官方 darwin-arm64 和
#   darwin-x64 两个包按 SHASUMS256.txt 校验后合成通用二进制，Apple 芯片和 Intel 的 Mac 都能跑
# - 额外的 --dart-define 可放在 EXTRA_DART_DEFINES 里
# - 签名：默认 ad-hoc（-）；有自己的证书时用 CODESIGN_IDENTITY 指定，钥匙串「始终允许」在重新构建后仍然有效
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "${FLUTTER_ROOT:-}" ]; then export PATH="$FLUTTER_ROOT/bin:$PATH"; fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# super_native_extensions（拖放、剪贴板）要用 Rust 编译；Homebrew 的 rustup 不把 cargo、rustc 放进 PATH
if [ -d /opt/homebrew/opt/rustup/bin ]; then export PATH="/opt/homebrew/opt/rustup/bin:$PATH"; fi

NODE_VERSION="${NODE_VERSION:-v24.18.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
CACHE="build/macos-runtime-cache"
APP_NAME=$(sed -n 's/^PRODUCT_NAME = //p' macos/Runner/Configs/AppInfo.xcconfig)

# 下载一个官方 Node 包并校验，解到缓存目录；输出解出来的目录
fetch_node_arch() {
  local arch="$1" base name dir expected actual
  base="https://nodejs.org/dist/$NODE_VERSION"
  name="node-$NODE_VERSION-darwin-$arch.tar.gz"
  dir="$CACHE/node-$NODE_VERSION-darwin-$arch"
  mkdir -p "$CACHE"
  if [ ! -x "$dir/bin/node" ]; then
    curl -fsSL "$base/SHASUMS256.txt" -o "$CACHE/SHASUMS256-$NODE_VERSION.txt"
    curl -fsSL "$base/$name" -o "$CACHE/$name"
    expected=$(grep " $name\$" "$CACHE/SHASUMS256-$NODE_VERSION.txt" | cut -d' ' -f1)
    actual=$(shasum -a 256 "$CACHE/$name" | cut -d' ' -f1)
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
      echo "Node 包校验不对：$name" >&2
      exit 1
    fi
    tar -xzf "$CACHE/$name" -C "$CACHE"
  fi
  echo "$dir"
}

bundle_tools() {
  local app="$1" arm x64 tools agent rel
  if [ ! -d "$app/Contents" ]; then
    echo "不是应用包：$app" >&2
    exit 2
  fi
  arm=$(fetch_node_arch arm64)
  x64=$(fetch_node_arch x64)
  tools="$app/Contents/Resources/tools"
  agent="$tools/nai-agent"
  rm -rf "$agent" "$tools/studio-bridge"
  mkdir -p "$agent"

  # Pi 的依赖：照 Windows 的准备脚本用 npm ci，用的是同一个版本 Node 带的 npm（纯 JS 依赖，不分架构）
  (cd tool/nai_agent && PATH="$OLDPWD/$arm/bin:$PATH" npm ci --no-audit --no-fund)

  # 照 scripts/windows_release_payload.py：tool/nai_agent 里跟踪的文件（不要 test/、node_modules/）+ node_modules
  while IFS= read -r -d '' file; do
    rel="${file#tool/nai_agent/}"
    case "$rel" in test/* | node_modules/*) continue ;; esac
    mkdir -p "$agent/$(dirname "$rel")"
    cp -p "$file" "$agent/$rel"
  done < <(git ls-files -z -- tool/nai_agent)
  cp -R tool/nai_agent/node_modules "$agent/node_modules"
  lipo -create "$arm/bin/node" "$x64/bin/node" -output "$agent/node"
  chmod 755 "$agent/node"
  cp -p "$arm/LICENSE" "$agent/NODE-LICENSE"
  if [ -f tool/nai_agent/node_modules/@earendil-works/pi-coding-agent/LICENSE ]; then
    cp -p tool/nai_agent/node_modules/@earendil-works/pi-coding-agent/LICENSE "$agent/PI-LICENSE"
  else
    cp -p tool/nai_agent/PI-LICENSE "$agent/PI-LICENSE"
  fi

  # 桥接客户端（Windows 包里是 studio-bridge.exe）
  dart compile exe tool/studio_bridge.dart -o "$tools/studio-bridge"

  # 先签里面的可执行文件和原生模块，再按原来的 entitlements 重签整个应用包（加了文件不重签，签名就对不上了）
  codesign --force --sign "$CODESIGN_IDENTITY" "$agent/node" "$tools/studio-bridge"
  find "$agent/node_modules" -name '*.node' -type f -exec codesign --force --sign "$CODESIGN_IDENTITY" {} \;
  codesign --force --sign "$CODESIGN_IDENTITY" \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$app"
  codesign --verify --deep --strict "$app"
  echo "已放进应用包：Node $("$agent/node" --version)（$(lipo -archs "$agent/node")）+ Pi，studio-bridge"
}

cmd="${1:-}"
case "$cmd" in
  tools)
    bundle_tools "$2"
    ;;
  "" | --release)
    mode=--debug
    out=Debug
    if [ "$cmd" = "--release" ]; then
      mode=--release
      out=Release
    fi
    # shellcheck disable=SC2086
    flutter build macos "$mode" ${EXTRA_DART_DEFINES:-}
    bundle_tools "build/macos/Build/Products/$out/$APP_NAME.app"
    ;;
  *)
    echo "用法：$0 [--release] | tools <应用包>" >&2
    exit 2
    ;;
esac
