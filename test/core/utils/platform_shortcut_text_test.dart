// 界面文案里的 Ctrl 快捷键在 macOS 上换成 ⌘ 的写法。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/platform_shortcut_text.dart';

void main() {
  const mac = TargetPlatform.macOS;

  test('macOS：组合键换成 ⌘ 符号', () {
    expect(
      platformShortcutText('全部替换（Ctrl+Enter）', platform: mac),
      '全部替换（⌘Enter）',
    );
    expect(platformShortcutText('撤销 (Ctrl+Z)', platform: mac), '撤销 (⌘Z)');
    expect(
      platformShortcutText('也可按 Ctrl+Shift+Space 或 Ctrl+单击', platform: mac),
      '也可按 ⇧⌘Space 或 ⌘+单击',
    );
    expect(
      platformShortcutText(
        'press Ctrl+Shift+Space or Ctrl+click a tag',
        platform: mac,
      ),
      'press ⇧⌘Space or ⌘+click a tag',
    );
    expect(platformShortcutText('Ctrl+クリック', platform: mac), '⌘+クリック');
  });

  test('其他平台原样', () {
    for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
      expect(platformShortcutText('撤销 (Ctrl+Z)', platform: p), '撤销 (Ctrl+Z)');
    }
  });
}
