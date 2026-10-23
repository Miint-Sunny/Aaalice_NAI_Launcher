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

  test('macOS：键帽上的键名换成 Mac 符号，界面写法和配置写法都认', () {
    const cases = {
      'Ctrl': '⌘',
      'ctrl': '⌘',
      'meta': '⌃',
      'Shift': '⇧',
      'alt': '⌥',
      'Enter': '⏎',
      'enter': '⏎',
      '↵': '⏎',
      'Esc': '⎋',
      'escape': '⎋',
      'Backspace': '⌫',
      'Delete': '⌦',
      'pagedown': '⇟',
      'comma': ',',
      'slash': '/',
      'arrowup': '↑',
      'k': 'K',
      'f11': 'F11',
      'F': 'F',
      ',': ',',
      '1…9': '1…9',
      // ⇱ ⇲ 自带字体里没有，照旧写字
      'Home': 'Home',
      'end': 'End',
    };
    for (final MapEntry(key: label, value: want) in cases.entries) {
      expect(platformKeyLabel(label, platform: mac), want, reason: label);
    }
    expect(platformKeyLabels(['Ctrl', 'Shift', 'T'], platform: mac), [
      '⇧',
      '⌘',
      'T',
    ]);
    expect(platformKeyLabels(['ctrl', 'meta', 'f'], platform: mac), [
      '⌃',
      '⌘',
      'F',
    ]);
    expect(platformKeyLabels(['W', 'A', 'S', 'D'], platform: mac), [
      'W',
      'A',
      'S',
      'D',
    ]);
    expect(platformKeysText(['ctrl', 'shift', 'm'], platform: mac), '⇧⌘M');
  });

  test('macOS：写在一行里的快捷键连写，不是快捷键的文字不动', () {
    const cases = {
      'Ctrl D': '⌘D',
      'Ctrl+V': '⌘V',
      'Ctrl+Shift+Z': '⇧⌘Z',
      'Enter': '⏎',
      'E': 'E',
      '0': '0',
      '3 项': '3 项',
      '1920×1080': '1920×1080',
      '只读': '只读',
    };
    for (final MapEntry(key: text, value: want) in cases.entries) {
      expect(platformShortcutLabel(text, platform: mac), want, reason: text);
    }
  });

  test('其他平台键名原样', () {
    for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
      expect(platformKeyLabel('Ctrl', platform: p), 'Ctrl');
      expect(platformKeyLabel('enter', platform: p), 'enter');
      expect(platformKeyLabels(['Ctrl', 'Shift', 'T'], platform: p), [
        'Ctrl',
        'Shift',
        'T',
      ]);
      expect(platformShortcutLabel('Ctrl D', platform: p), 'Ctrl D');
      expect(
        platformKeysText(['ctrl', 'shift', 'm'], platform: p),
        'ctrl+shift+m',
      );
    }
  });
}
