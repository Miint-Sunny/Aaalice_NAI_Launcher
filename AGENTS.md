# AGENTS.md — NAI Launcher · macOS 适配开发须知

> 本文件是 macOS 适配的开发 handoff 文档，**随本 fork 仓库分发**，供任意 AI agent
> （Claude Code / Codex / zcode 等）和人工接手者快速上手。
> Claude Code 用户：根目录 `CLAUDE.md` 已用 `@` 指向本文件，会自动加载。
> ⚠️ 文档中明确标注了**哪些改动属 macOS 适配、哪些是本机 SDK 兼容补丁（不应进给上游的 PR）**，见 §3、§5。
> 最后更新：2026-06-16。

---

## 0. 一句话现状

Flutter 跨平台 NovelAI 客户端（原支持 Windows + Android），**已完成 macOS 适配并端到端验证通过**，PR [#52](https://github.com/Aaalice233/Aaalice_NAI_Launcher/pull/52) 已提，等上游作者 review。本机用 **Flutter 3.44.2**，项目原目标约 3.24，存在 SDK 版本鸿沟（见 §3）。

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

---

## 2. 🕳 必读陷阱（已踩过，别再踩）

1. **Git LFS 数据库**：`assets/databases/*.db` 是 LFS 文件。clone 后**必须** `git lfs pull`，否则只有 ~132B 指针，sqlite 报 `file is not a database (code 26)`。真实大小：`translation.db` 4.4MB、`cooccurrence.db` 321MB。
2. **生成代码**：clone 后或改了 freezed/json/riverpod 注解，**必须**跑 `dart run build_runner build --delete-conflicting-outputs`，否则编译报 getter 缺失 / switch 不穷尽（仓库不含生成产物）。
3. **Keychain 签名**：见 §1。macOS 上 `flutter_secure_storage` 用 **login keychain**（代码层 `MacOsOptions(useDataProtectionKeyChain: false)`，零证书依赖）；data protection keychain + `keychain-access-groups` entitlement **会让 ad-hoc 构建直接失败**（需开发者证书）。
4. **CocoaPods UTF-8**：任何触发 pod install 的命令前 `export LANG=en_US.UTF-8`，否则 pod 报编码错。
5. **窗口尺寸**：macOS 启动时用 `screen_retriever` 读屏幕工作区并铺满（`lib/main.dart`）。默认 1600×900 在 13" Mac（逻辑 1470×956）会超出屏幕。

---

## 3. SDK 版本鸿沟（关键，影响 PR 边界）

本机 Flutter 3.44.2 ≠ 项目原目标（约 3.24）。为在新 SDK 构建做了一批**与 macOS 无关**的兼容补丁，**绝不能进 macOS PR**（上游若用旧 SDK 会编译失败，例如 `DialogThemeData` 在旧 Flutter 不存在）：

- `intl ^0.19 → ^0.20.2`（flutter_localizations 钉死 0.20）
- 移除 `glados`（其老版 analyzer 与新 SDK + hive_generator/freezed 冲突）
- `DialogTheme → DialogThemeData`、`CardTheme → CardThemeData`（Flutter 主题 API 迁移，6 处）

已在 issue #51 跟作者商量是否升级 SDK；若升级，可把下方 commit `b119b2c6` 整理成单独的 SDK 升级 PR。

---

## 4. 分支结构

| 分支 | 内容 | 用途 |
|------|------|------|
| `feat/macos-support` | commit `04a69495`(A 适配) + `b119b2c6`(B+C 兼容) | **本地开发/运行**，3.44 可跑 |
| `pr/macos` | 仅 `04a69495`（A） | 已 push → fork，对应 **PR #52**（上游旧 SDK 可直接 build） |

提 PR 永远基于 `pr/macos`（纯 A）。本地开发待在 `feat/macos-support`。
`pr/macos` 在本机 3.44 **build 不了**（缺 B），其旧-SDK 可构建性靠代码审查 + 作者/CI。

---

## 5. 改动分类（A 进 PR / B+C 不进）

- **A — macOS 适配（进 PR，commit `04a69495`）**：
  `macos/` 目录、`lib/main.dart`（视频按平台初始化 + 窗口自适应）、`sqflite_bootstrap_service.dart`、`secure_storage_service.dart`、`history_panel.dart`、三处剪贴板（`selectable_image_card.dart` / `local_image_card_3d.dart` / `image_detail_viewer.dart` 改用 super_clipboard）、README、`.gitignore`、`scripts/build_release_macos.sh` + 签名脚本、pubspec 仅加 `media_kit_libs_macos_video` + `screen_retriever`。
- **B — SDK 兼容（不进 PR，commit `b119b2c6` 一部分）**：见 §3。
- **C — 生成产物（不进 PR）**：`.metadata`、`pubspec.lock`、`lib/l10n/*`、`*.g.dart`、`windows/flutter/generated_plugins.cmake`。

---

## 6. 设计取舍 / 已知限制

- **关闭了 App Sandbox**（`macos/Runner/*.entitlements`）：为支持 `Process.run`、读写用户目录、Keychain、网络。代价：不能上 Mac App Store（项目本就独立分发，OK）。上 MAS 需重开沙盒并逐项补 entitlements。
- **系统托盘未实现**：macOS 下关窗口 = 退出应用。后续迭代项（托盘图标需从 `.ico` 换 `.png` template image）。
- **bundle id `com.example.nai_launcher` 含下划线**：Apple 平台有 warning，本地 ad-hoc 运行无碍；正式签名/公证前建议改无下划线（如 `com.example.naiLauncher`）。

---

## 7. 验证清单（改完 macOS 相关代码后回归）

启动后看日志（`~/Documents/NAI_Launcher/logs/app_*.log`）确认：
`Sqflite FFI initialized` → `Translation data source initialized with 33874 records` → `Window filled to work area` → 登录后 `Subscription loaded`，且**无** `errSecMissingEntitlement / -34018 / Unhandled Exception`。
触及共享代码（剪贴板 / 视频 / 窗口）时，提醒在 **Windows 回归**。
