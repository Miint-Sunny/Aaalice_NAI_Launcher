# AGENTS.md — NAI Launcher · macOS 适配开发须知

> 本文件是 macOS 适配的开发 handoff 文档，**随本 fork 仓库分发**，供任意 AI agent
> （Claude Code / Codex / zcode 等）和人工接手者快速上手。
> Claude Code 用户：根目录 `CLAUDE.md` 已用 `@` 指向本文件，会自动加载。
> ⚠️ 上游已合并依赖统一大 PR（#54），原先「不应进 PR 的 SDK 兼容补丁」已被上游做掉，见 §3、§5。
> 最后更新：2026-06-21。

---

## 0. 一句话现状

Flutter 跨平台 NovelAI 客户端（原支持 Windows + Android），**已完成 macOS 适配并端到端验证通过**。PR [#52](https://github.com/Aaalice233/Aaalice_NAI_Launcher/pull/52)（macOS 最小适配）**已被上游合并**（2026-06-21，merge `ac1aa84e`，随 **v1.0.0-beta13** 发布）—— macOS 适配现已是上游官方一部分，README 平台表已列「macOS 最小适配」。更早上游也合并了依赖统一大 PR（#54），SDK 抬到 **Flutter ≥3.35 / Dart ≥3.10.7**，与本机 **Flutter 3.44.2** 兼容（见 §3）。`main` / `feat` 均已同步到 beta13（`17dc9662`）。

- 上游：`Aaalice233/Aaalice_NAI_Launcher`　fork：`Miint-Sunny/Aaalice_NAI_Launcher`
- 本地路径：`/Users/suzuhashimizu/code/Aaalice_NAI_Launcher_macOS`

---

## 1. ⛔ 最重要：如何构建 / 运行（macOS）

```bash
# 日常开发：build + 自签名证书重签 + 启动（避免 keychain 每次弹授权框）
scripts/dev_run_macos_signed.sh           # 默认 debug；release 用：... release

# 证书丢了 / 换机器后重建签名证书
scripts/create_macos_dev_cert.sh
```

- **不要用 `flutter run`**：它用 ad-hoc 签名，会导致 `flutter_secure_storage` 每次访问 Keychain 弹授权框。必须用上面的脚本（稳定证书签名后 Always Allow 一次永久生效）。
- 纯构建（不关心弹框）：`LANG=en_US.UTF-8 flutter build macos`（CocoaPods 需要 UTF-8 编码，**必须**带 `LANG`）。
- 证书 "NAI Launcher Local Dev" 在独立钥匙串 `~/Library/Keychains/nai-codesign.keychain-db`（密码 `naidev`），不碰用户 login 钥匙串。
- **应用/托盘图标**：圆角方块（白底 squircle + 角色立绘）。生成工具 `tool/macos_icon/`（Pillow，用 venv）：`make_macos_icons.py` 覆盖 AppIcon 各尺寸 + `tray_icon.png`；`--char-scale` 调白边宽度；`--previews` 出白边对比图（`previews/` 有 A/B/C 变体）。改图标后需重新 `flutter build macos`。

---

## 2. 🕳 必读陷阱（已踩过，别再踩）

1. **Git LFS 数据库**：`assets/databases/*.db` 是 LFS 文件。clone 后**必须** `git lfs pull`，否则只有 ~132B 指针，sqlite 报 `file is not a database (code 26)`。真实大小：`translation.db` 4.4MB、`cooccurrence.db` 321MB。
2. **生成代码**：clone 后或改了 freezed/json/riverpod 注解，**必须**跑 `dart run build_runner build --delete-conflicting-outputs`，否则编译报 getter 缺失 / switch 不穷尽（仓库不含生成产物）。
3. **Keychain 签名**：见 §1。macOS 上 `flutter_secure_storage` 用 **login keychain**（代码层 `MacOsOptions(useDataProtectionKeyChain: false)`，零证书依赖）；data protection keychain + `keychain-access-groups` entitlement **会让 ad-hoc 构建直接失败**（需开发者证书）。
4. **CocoaPods UTF-8**：任何触发 pod install 的命令前 `export LANG=en_US.UTF-8`，否则 pod 报编码错。
5. **窗口尺寸**：macOS 启动时用 `screen_retriever` 读屏幕工作区并铺满（`lib/main.dart`）。默认 1600×900 在 13" Mac（逻辑 1470×956）会超出屏幕。
6. **Xcode 26.5 + 旧 `macos/Podfile.lock` → 链接失败**：报 `Undefined symbols ... AudioplayersDarwinPlugin` + `CoreAudioTypes framework not found`。初次适配留的 Podfile.lock 不含上游后加的插件（`onnxruntime` 等）。**修复：clean 重装 pod** —— `flutter clean && rm -rf macos/Pods macos/Podfile.lock macos/Flutter/ephemeral build && flutter pub get && flutter build macos`（新 lock 已提交）。

---

## 3. SDK 版本（历史问题，现已解决）

之前本机 Flutter 3.44.2 与项目原目标（约 3.24）的鸿沟**已不存在**：上游 2026-06-19 合并了依赖统一大 PR（[#54](https://github.com/Aaalice233/Aaalice_NAI_Launcher/pull/54)，+13 万行/685 文件），新 `main`（beta12）已自带当初为新 SDK 做的全部兼容改动，SDK 也抬到 `>=3.10.7 / flutter >=3.35.0`：

- `intl ^0.20.2`、移除 `glados`、`DialogTheme→DialogThemeData` / `CardTheme→CardThemeData` —— **均已在上游 `main`**。
- 含义：原先要刻意排除在 PR 外的「B 类 SDK 补丁」已无意义；之前备好的 `chore/flutter-3.44-upgrade` 分支**已作废**（别再 push）。
- 本机 Flutter 3.44 与新 `main` 兼容，`pr/macos` / `feat` 现在都能直接 `flutter build macos`。

---

## 4. 分支结构

| 分支 | 内容 | 用途 |
|------|------|------|
| `feat/macos-support` | = 上游 `main`（beta13）+ 托盘/窗口生命周期 + AGENTS/CLAUDE 文档 + `scripts/build_dmg.sh`。已 push fork | **本地开发/运行**全功能版（含托盘）；fork Release 从这里出 |
| `pr/macos-tray` | 上游 `main` + 仅托盘 1 commit（main.dart/AppDelegate/tray_icon）| 托盘 **follow-up PR** 已备好，**未 push、未开 PR**（发 PR 命令见本地草稿 `/tmp/tray_pr.md`）|

`pr/macos` 分支已随 PR #52 合并而**作废删除**（内容已在上游 `main`）。本地开发待在 `feat/macos-support`。
备份分支 `feat-bak`（本轮 rebase 前的 feat）仍在，确认无误可删。

---

## 5. 改动分类（A 进 PR / B+C 不进）

- **A — macOS 适配（PR #52 主体）**：
  `macos/` 目录、`lib/main.dart`（视频按平台初始化 + 窗口自适应）、`sqflite_bootstrap_service.dart`、`secure_storage_service.dart`、三处剪贴板（`selectable_image_card.dart` / `local_image_card_3d.dart` / `image_detail_viewer.dart` 保留 main 的 `ImageShareSanitizer` 剥离管线，写入改用 `lib/presentation/utils/clipboard_image.dart` 统一规范化 PNG）、README、`.gitignore`、签名脚本、pubspec 加 `media_kit_libs_macos_video` + `screen_retriever` + 同步 lockfile。`history_panel` 的「在文件夹定位」上游已重构进 `FileExplorerUtils.revealFile`（含 macOS `open -R`），**无需再改**。
- **B — SDK 兼容**：~~曾需手动打~~ **已废**，上游 `main` 自带（见 §3）。
- **C — 生成产物**：`*.g.dart` / `.metadata` 仍不手动维护（`build_runner` 生成）。⚠️ 新 `main` 把 `lib/l10n/app_localizations*.dart`、`pubspec.lock`、`macos/Podfile.lock` **纳入 git 跟踪**，改依赖/l10n 后要一并提交。
- **功能补全（仅 `feat`，未进上游）**：系统托盘 + 窗口生命周期 —— 主 PR #52 已 merge，**follow-up PR 已备好**（分支 `pr/macos-tray`，仅托盘 1 commit，未 push）。圆角 AppIcon + `tool/macos_icon` 工具已随 PR #52 进上游。

---

## 6. 设计取舍 / 已知限制

- **关闭了 App Sandbox**（`macos/Runner/*.entitlements`）：为支持 `Process.run`、读写用户目录、Keychain、网络。代价：不能上 Mac App Store（项目本就独立分发，OK）。上 MAS 需重开沙盒并逐项补 entitlements。
- **系统托盘 + 窗口生命周期闭环**（commit `30f8b834`，在 `feat`，已验证）：菜单栏托盘（`assets/icons/tray_icon.png`）、关窗口隐藏到托盘、Dock/托盘恢复窗口、Cmd+Q 与托盘"退出"正常退出。Swift 层 `macos/Runner/AppDelegate.swift` 加了 `applicationShouldHandleReopen`（点 Dock 恢复）+ `applicationShouldTerminateAfterLastWindowClosed=false`（隐藏不退出）；Dart 层把托盘初始化条件从 `if(isWindows)` 扩到 `if(isWindows||isMacOS)`。**主 PR #52 已 merge**，已备好 follow-up PR 分支 `pr/macos-tray`（未 push）。
- **bundle id `com.example.nai_launcher` 含下划线**：Apple 平台有 warning，本地 ad-hoc 运行无碍；正式签名/公证前建议改无下划线（如 `com.example.naiLauncher`）。

---

## 7. 验证清单（改完 macOS 相关代码后回归）

启动后看日志（`~/Documents/NAI_Launcher/logs/app_*.log`）确认：
`Sqflite FFI initialized` → `Translation data source initialized with 33874 records` → `Window filled to work area` → 登录后 `Subscription loaded`，且**无** `errSecMissingEntitlement / -34018 / Unhandled Exception`。
触及共享代码（剪贴板 / 视频 / 窗口）时，提醒在 **Windows 回归**。

---

## 8. 本地数据目录（用户数据 / 调试）

按 **bundle id** `com.example.nai_launcher` 定位（与应用名、`.app` 包无关——改 bundle id 才会换目录，所以重新构建/改应用名后数据照样在）：

- **Hive 本地库**：`~/Library/Application Support/com.example.nai_launcher/hive/`
  - `settings.hive` — 设置 + 上次 prompt：`last_prompt`(正面) / `last_negative_prompt`(负面) / `character_prompt_config`·`characters`(角色)，以及代理/主题/窗口尺寸等。**prompt 与其它设置同在此 box，不能单独删 prompt**（删整个文件会丢全部设置）。
  - 其它：`accounts.hive`、`scan_state.hive`、`local_metadata_cache.hive` 等（`prompt_configs.hive` 当前空、未使用）。
- **预构建数据库**：`~/Library/Application Support/com.example.nai_launcher/asset_databases/`（`translation.db` / `cooccurrence.db`，启动时从 assets 复制）。
- **图片 / 日志**：`~/Documents/NAI_Launcher/`（`images/`、`logs/app_*.log`）；vibes 在 `~/Documents/NAI_Launcher/vibes`。
- **token**：login keychain（见 §1，非文件；自签名证书 + dev_run 脚本免弹框）。

排查「重新构建后数据还在 / 想重置」类问题看这里。

---

## 9. 外部依赖 / 工具链

**构建必需：**
- **Flutter SDK**（本机 3.44.2）+ **完整 Xcode**（非 CLT，装后 `sudo xcodebuild -license accept`）+ **CocoaPods**（`brew install cocoapods`）
- **Git LFS**（`brew install git-lfs && git lfs pull`）：`assets/databases/*.db` 是 LFS（见 §2）
- codegen：`flutter pub get` → `dart run build_runner build --delete-conflicting-outputs` → `flutter gen-l10n`

**可选工具（本地分发 / 美化）：**
- **create-dmg**（`brew install create-dmg`）：DMG 打包 → `scripts/build_dmg.sh`
- **Pillow**（`python3 -m venv venv && venv/bin/pip install Pillow`）：图标生成 → `tool/macos_icon/`
- 自签名证书：`scripts/create_macos_dev_cert.sh`（openssl + security，免 keychain 弹框）

**scripts/ 一览：**
| 脚本 | 作用 |
|------|------|
| `create_macos_dev_cert.sh` | 建本地签名证书（独立钥匙串 `nai-codesign`，密码 `naidev`） |
| `dev_run_macos_signed.sh [debug\|release]` | 日常：build + 证书重签 + 启动（免 keychain 弹框） |
| `build_dmg.sh` | release 构建 + 重签 + create-dmg 打包成 `build/Aaalice_NAI_Launcher.dmg` |
| `build_release_macos.sh` | release 构建（对标 Windows 的 `build_release.bat`） |

**DMG 分发**：Release 已发在 fork（[macos-v1.0.0-beta7](https://github.com/Miint-Sunny/Aaalice_NAI_Launcher/releases/tag/macos-v1.0.0-beta7)）。自签名未公证，下载者首次需 `xattr -dr com.apple.quarantine "/Applications/Aaalice NAI Launcher.app"`。
