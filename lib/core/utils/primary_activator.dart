import 'package:flutter/widgets.dart';

import 'desktop_platform.dart';

/// 主修饰键的组合键：macOS 上是 ⌘，其他平台是 Ctrl（同快捷键配置里的 ctrl，见 ShortcutParser）。
///
/// 只绑了 Ctrl 的 `SingleActivator(key, control: true)` 换成 `PrimaryActivator(key)`：Windows 上不变，
/// Mac 上按 ⌘ 触发、按 Control 不触发。平台在按键时才判断，可以写成 const。
class PrimaryActivator extends SingleActivator {
  const PrimaryActivator(
    super.trigger, {
    super.shift,
    super.alt,
    super.includeRepeats,
  });

  @override
  bool get control => !usesMacOSConventions;

  @override
  bool get meta => usesMacOSConventions;
}
