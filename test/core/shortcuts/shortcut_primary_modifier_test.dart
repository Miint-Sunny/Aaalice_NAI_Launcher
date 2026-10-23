// macOS 按规范用 ⌘ 当主修饰键（配置里的 ctrl 在 Mac 上是 ⌘，Mac 的 Control 键记成 meta）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_manager.dart';

ParsedShortcut _pressed(Set<ShortcutModifier> modifiers, ShortcutKey key) =>
    ParsedShortcut(modifiers: modifiers, key: key, raw: '');

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS：配置里的 ctrl 解析成 ⌘，存回去还是 ctrl', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final parsed = ShortcutParser.parse('ctrl+shift+enter')!;
    expect(parsed.modifiers, {ShortcutModifier.meta, ShortcutModifier.shift});
    expect(ShortcutParser.serialize(parsed), 'ctrl+shift+enter');
    expect(AppShortcutManager.normalize('meta+k'), 'meta+k');
  });

  test('macOS：录制时按 ⌘ 存成 ctrl，按 Control 存成 meta', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(
      ShortcutParser.serialize(
        _pressed({ShortcutModifier.meta}, ShortcutKey.keyK),
      ),
      'ctrl+k',
    );
    expect(
      ShortcutParser.serialize(
        _pressed({ShortcutModifier.control}, ShortcutKey.keyK),
      ),
      'meta+k',
    );
  });

  test('macOS：按 ⌘ 触发，显示成 ⌘1 这样的符号', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final activator =
        AppShortcutManager.parseActivator('ctrl+1')! as LogicalKeySet;
    expect(activator.keys, contains(LogicalKeyboardKey.meta));
    expect(activator.keys, isNot(contains(LogicalKeyboardKey.control)));
    expect(AppShortcutManager.getDisplayLabel('ctrl+1'), '⌘1');
    expect(AppShortcutManager.getDisplayLabel('ctrl+shift+t'), '⇧⌘T');
    expect(AppShortcutManager.getDisplayLabel('ctrl+enter'), '⌘⏎');
    expect(AppShortcutManager.getDisplayLabel('escape'), '⎋');
  });

  test('Windows：照旧是 Ctrl', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final parsed = ShortcutParser.parse('ctrl+1')!;
    expect(parsed.modifiers, {ShortcutModifier.control});
    expect(ShortcutParser.serialize(parsed), 'ctrl+1');
    final activator =
        AppShortcutManager.parseActivator('ctrl+1')! as LogicalKeySet;
    expect(activator.keys, contains(LogicalKeyboardKey.control));
    expect(AppShortcutManager.getDisplayLabel('ctrl+1'), 'Ctrl+1');
  });
}
