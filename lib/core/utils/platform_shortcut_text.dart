import 'package:flutter/foundation.dart';

/// 界面文案里写的 Ctrl 快捷键，macOS 上按规范换成 ⌘ 的写法；其他平台原样。
///
/// Ctrl+Shift+Space → ⇧⌘Space，Ctrl+Enter → ⌘Enter，Ctrl+单击 / Ctrl+click → ⌘+单击 / ⌘+click。
/// 文案本身（ARB）不动，调用处套一层即可。
String platformShortcutText(String text, {TargetPlatform? platform}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.macOS) return text;
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
