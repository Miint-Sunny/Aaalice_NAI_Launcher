import 'package:flutter/foundation.dart';

import '../shortcuts/shortcut_config.dart';

/// 界面文案里写的 Ctrl 快捷键，macOS 上按规范换成 ⌘ 的写法；其他平台原样。
///
/// Ctrl+Shift+Space → ⇧⌘Space，Ctrl+Enter → ⌘Enter，Ctrl+单击 / Ctrl+click → ⌘+单击 / ⌘+click。
/// 文案本身（ARB）不动，调用处套一层即可。
String platformShortcutText(String text, {TargetPlatform? platform}) {
  if (!_isMac(platform)) return text;
  return text
      .replaceAllMapped(
        RegExp(r'Ctrl\+Shift\+(?![Cc]lick)(?=[A-Za-z0-9])'),
        (_) => '⇧⌘',
      )
      .replaceAllMapped(
        RegExp(r'Ctrl\+(?![Cc]lick)(?=[A-Za-z0-9])'),
        (_) => '⌘',
      )
      .replaceAll('Ctrl', '⌘');
}

/// 键帽上的一个键名按平台写：macOS 用 Mac 键盘符号（⌘ ⌥ ⇧ ⌃ ⏎ ⎋ ⌫……），其他平台原样。
///
/// 界面里写的键名（Ctrl、Shift、Enter、Esc……）和配置里存的写法（ctrl、shift、enter、comma……）都认。
/// 两种写法里的 Ctrl 都指主修饰键，Mac 上是 ⌘；配置里的 meta 在 Mac 上是 Control（⌃），同 ShortcutParser。
String platformKeyLabel(String key, {TargetPlatform? platform}) =>
    _isMac(platform) ? _macKeyLabels[key.trim().toLowerCase()] ?? key : key;

/// 一组键帽：macOS 上逐个换成 Mac 写法，修饰键按 Mac 菜单的顺序（⌃⌥⇧⌘）排在前面；其他平台原样。
List<String> platformKeyLabels(List<String> keys, {TargetPlatform? platform}) {
  if (!_isMac(platform)) return keys;
  final labels = [
    for (final k in keys) platformKeyLabel(k, platform: platform),
  ];
  return [
    for (final m in _macModifiers)
      if (labels.contains(m)) m,
    ...labels.where((k) => !_macModifiers.contains(k)),
  ];
}

/// 写在一行里的快捷键（菜单右侧的 `Ctrl D`、`Ctrl+V`）：macOS 上换成 ⌘D 这样连写的 Mac 写法；
/// 不像快捷键的文字原样返回。其他平台原样。
String platformShortcutLabel(String text, {TargetPlatform? platform}) {
  if (!_isMac(platform)) return text;
  final keys = [
    for (final k in text.split(RegExp(r'[+\s]+')))
      if (k.isNotEmpty) k,
  ];
  if (keys.isEmpty || !keys.every(_isKeyName)) return text;
  final labels = platformKeyLabels(keys, platform: platform);
  // 没有要换的键（例如单个字母键）就不动，免得把文字里的空格去掉
  return listEquals(labels, keys) ? text : labels.join();
}

/// 列表里「删除」键的写法（见 isListDeleteKey）：macOS 上是 ⌘⌫，其他平台是 Del。
String listDeleteKeyLabel({TargetPlatform? platform}) =>
    _isMac(platform) ? '⌘⌫' : 'Del';

/// 一组键写成一行（「默认是 …」这类说明里用）：macOS 上连写（⇧⌘M），其他平台用 + 连接。
String platformKeysText(List<String> keys, {TargetPlatform? platform}) =>
    _isMac(platform)
    ? platformKeyLabels(keys, platform: platform).join()
    : keys.join('+');

bool _isMac(TargetPlatform? platform) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.macOS;

bool _isKeyName(String key) =>
    key.runes.length == 1 || _macKeyLabels.containsKey(key.toLowerCase());

const _macModifiers = ['⌃', '⌥', '⇧', '⌘'];

// 键名（小写）→ Mac 写法。特殊键的符号见 ShortcutKey.macLabel
final _macKeyLabels = {
  for (final key in ShortcutKey.values) ...{
    key.logicalKey: key.macLabel,
    key.displayName.toLowerCase(): key.macLabel,
  },
  'ctrl': '⌘',
  'meta': '⌃',
  'alt': '⌥',
  'shift': '⇧',
  'esc': '⎋',
  'del': '⌦',
  '↵': '⏎',
};
