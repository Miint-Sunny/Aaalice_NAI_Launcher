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
# - studio-bridge：--release 时也合成通用二进制。dart compile exe 只编本机架构，Intel 那一份用官方的
#   macOS x64 Dart SDK（和 Flutter 自带的 Dart 同一版本，按 .sha256sum 校验）在 Rosetta 下编，所以要在
#   装了 Rosetta 的 Apple 芯片 Mac 上构建；做不到时只编本机架构并提示，这样的包 package_macos_release.sh
#   默认不收。debug 和 tools 只编本机架构
# - 发布包：构建完用 scripts/package_macos_release.sh 打成 zip
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

# 下载卡住（一分钟不到 1 KB/s）就断开重试，不让构建一直挂着
download() {
  curl -fsSL --retry 3 --retry-all-errors --connect-timeout 30 \
    --speed-limit 1024 --speed-time 60 "$1" -o "$2"
}

# 下载一个官方 Dart SDK（macOS x64，版本和频道同 PATH 上的 dart）并校验，解到缓存目录；输出 SDK 目录
fetch_dart_x64() {
  local version channel base name dir expected actual
  read -r version channel < <(dart --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\) (\([a-z]*\)).*/\1 \2/p') || true
  if [ -z "$version" ]; then
    echo "读不出 Dart 版本" >&2
    exit 1
  fi
  base="https://storage.googleapis.com/dart-archive/channels/$channel/release/$version/sdk"
  name="dartsdk-macos-x64-release.zip"
  dir="$CACHE/dart-sdk-$version-macos-x64"
  mkdir -p "$CACHE"
  if [ ! -x "$dir/dart-sdk/bin/dart" ]; then
    download "$base/$name.sha256sum" "$CACHE/$name-$version.sha256sum"
    download "$base/$name" "$CACHE/$name"
    expected=$(cut -d' ' -f1 < "$CACHE/$name-$version.sha256sum")
    actual=$(shasum -a 256 "$CACHE/$name" | cut -d' ' -f1)
    if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
      echo "Dart SDK 包校验不对：$name" >&2
      exit 1
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    ditto -x -k "$CACHE/$name" "$dir"
    rm -f "$CACHE/$name"
    if [ ! -x "$dir/dart-sdk/bin/dart" ]; then
      echo "Dart SDK 包解压失败：$name" >&2
      exit 1
    fi
  fi
  echo "$dir/dart-sdk"
}

# 编桥接客户端。第二个参数是 universal 时再编一份 x86_64 合成通用二进制；第三个参数是一个
# x86_64 的可执行文件，用来试 Rosetta 能不能用
build_studio_bridge() {
  local out="$1" archs="$2" probe="$3" x64
  dart compile exe tool/studio_bridge.dart -o "$out"
  if [ "$archs" != universal ]; then
    return
  fi
  if [ "$(uname -m)" != arm64 ] || ! arch -x86_64 "$probe" --version >/dev/null 2>&1; then
    echo "警告：studio-bridge 只编了本机架构（$(uname -m)），Intel 版要在装了 Rosetta 的 Apple 芯片 Mac 上编（softwareupdate --install-rosetta）。这样的包只能自己用，不要发布" >&2
    return
  fi
  x64=$(fetch_dart_x64)
  arch -x86_64 "$x64/bin/dart" compile exe tool/studio_bridge.dart -o "$out-x86_64"
  lipo -create "$out" "$out-x86_64" -output "$out-universal"
  mv "$out-universal" "$out"
  rm -f "$out-x86_64"
}

# 下载一个官方 Node 包并校验，解到缓存目录；输出解出来的目录
fetch_node_arch() {
  local arch="$1" base name dir expected actual
  base="https://nodejs.org/dist/$NODE_VERSION"
  name="node-$NODE_VERSION-darwin-$arch.tar.gz"
  dir="$CACHE/node-$NODE_VERSION-darwin-$arch"
  mkdir -p "$CACHE"
  if [ ! -x "$dir/bin/node" ]; then
    download "$base/SHASUMS256.txt" "$CACHE/SHASUMS256-$NODE_VERSION.txt"
    download "$base/$name" "$CACHE/$name"
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
  local app="$1" bridge_archs="${2:-host}" arm x64 tools agent rel
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
  build_studio_bridge "$tools/studio-bridge" "$bridge_archs" "$x64/bin/node"

  # 先签里面的可执行文件和原生模块，再按原来的 entitlements 重签整个应用包（加了文件不重签，签名就对不上了）
  codesign --force --sign "$CODESIGN_IDENTITY" "$agent/node" "$tools/studio-bridge"
  find "$agent/node_modules" -name '*.node' -type f -exec codesign --force --sign "$CODESIGN_IDENTITY" {} \;
  codesign --force --sign "$CODESIGN_IDENTITY" \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$app"
  codesign --verify --deep --strict "$app"
  echo "已放进应用包：Node $("$agent/node" --version)（$(lipo -archs "$agent/node")）+ Pi，studio-bridge（$(lipo -archs "$tools/studio-bridge")）"
}

cmd="${1:-}"
case "$cmd" in
  tools)
    bundle_tools "$2"
    ;;
  "" | --release)
    mode=--debug
    out=Debug
    bridge_archs=host
    if [ "$cmd" = "--release" ]; then
      mode=--release
      out=Release
      bridge_archs=universal
    fi
    # shellcheck disable=SC2086
    flutter build macos "$mode" ${EXTRA_DART_DEFINES:-}
    bundle_tools "build/macos/Build/Products/$out/$APP_NAME.app" "$bridge_archs"
    ;;
  *)
    echo "用法：$0 [--release] | tools <应用包>" >&2
    exit 2
    ;;
esac
