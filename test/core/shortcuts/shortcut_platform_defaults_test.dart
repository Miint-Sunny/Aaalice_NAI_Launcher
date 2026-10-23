// macOS 上按不到或被系统占用的默认键换成 Mac 习惯键；已存配置读取时（withCurrentDefaults）对齐到本平台。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/shortcuts/default_shortcuts.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_manager.dart';

String _label(String id) =>
    AppShortcutManager.getDisplayLabel(DefaultShortcuts.all[id]);

ShortcutConfig _storedWith(String id, String storedDefault, {String? custom}) {
  final config = ShortcutConfig.createDefault();
  return config.updateBinding(
    config.bindings[id]!.copyWith(
      defaultShortcut: storedDefault,
      customShortcut: custom,
    ),
  );
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS：删除 ⌘⌫、刷新 ⌘R、快捷键帮助 ⌘/、切换正/负面 ⇧⌘M', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(_label(ShortcutIds.deleteImage), '⌘⌫');
    expect(_label(ShortcutIds.vibeDetailDelete), '⌘⌫');
    expect(_label(ShortcutIds.refreshGallery), '⌘R');
    expect(_label(ShortcutIds.showShortcutHelp), '⌘/');
    expect(_label(ShortcutIds.togglePromptMode), '⇧⌘M');
  });

  test('macOS：窗口键交给系统菜单，占用它们的几项默认不设键', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final config = ShortcutConfig.createDefault();
    for (final id in [
      ShortcutIds.minimizeToTray,
      ShortcutIds.quitApp,
      ShortcutIds.toggleFullscreen,
      ShortcutIds.fullscreenPreview,
    ]) {
      expect(config.getEffectiveShortcut(id) ?? '', isEmpty, reason: id);
    }
    // 没有哪一项默认占着 ⌘M ⌘Q ⌘W ⌘H ⌃⌘F
    final taken = {
      for (final id in DefaultShortcuts.all.keys)
        if (config.getEffectiveShortcut(id) case final shortcut?
            when shortcut.isNotEmpty)
          AppShortcutManager.getDisplayLabel(shortcut),
    };
    for (final systemKey in ['⌘M', '⌘Q', '⌘W', '⌘H', '⌃⌘F']) {
      expect(taken, isNot(contains(systemKey)), reason: systemKey);
    }
  });

  test('Windows：沿用 W.O.F 原值', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    for (final MapEntry(key: id, value: (wof, _))
        in DefaultShortcuts.macOverrides.entries) {
      expect(DefaultShortcuts.all[id], wof, reason: id);
    }
  });

  test('macOS：存下的 Windows 默认值读取时换成 Mac 的，自定义的不动', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final refreshed = _storedWith(
      ShortcutIds.deleteImage,
      'delete',
    ).withCurrentDefaults();
    expect(
      refreshed.getEffectiveShortcut(ShortcutIds.deleteImage),
      'ctrl+backspace',
    );

    final custom = _storedWith(
      ShortcutIds.toggleFullscreen,
      'f11',
      custom: 'f12',
    ).withCurrentDefaults();
    expect(custom.getEffectiveShortcut(ShortcutIds.toggleFullscreen), 'f12');

    final quit = _storedWith(
      ShortcutIds.quitApp,
      'ctrl+q',
    ).withCurrentDefaults();
    expect(quit.getEffectiveShortcut(ShortcutIds.quitApp) ?? '', isEmpty);
  });

  test('Windows：从 Mac 导入的默认值换回 W.O.F 原值', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final refreshed = _storedWith(
      ShortcutIds.refreshGallery,
      'ctrl+r',
    ).withCurrentDefaults();
    expect(refreshed.getEffectiveShortcut(ShortcutIds.refreshGallery), 'f5');

    final quit = _storedWith(ShortcutIds.quitApp, '').withCurrentDefaults();
    expect(quit.getEffectiveShortcut(ShortcutIds.quitApp), 'ctrl+q');
  });
}
