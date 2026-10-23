import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/utils/desktop_platform.dart';

/// macOS 输入框补充的编辑键：⌘Y 也能重做（系统自带的是 ⇧⌘Z，照旧能用）。
///
/// 放在应用层，对所有输入框生效；焦点不在输入框里时找不到「重做」，按键原样往外传，
/// 不影响图库自己的 ⌘Y 和系统菜单。其他平台原样返回 [child]：Windows 的 Ctrl+Y 由输入框自己加。
class MacTextEditingShortcuts extends StatelessWidget {
  const MacTextEditingShortcuts({super.key, required this.child});

  final Widget child;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyY, meta: true): RedoTextIntent(
      SelectionChangedCause.keyboard,
    ),
  };

  @override
  Widget build(BuildContext context) {
    if (!usesMacOSConventions) return child;
    return Shortcuts(shortcuts: _shortcuts, child: child);
  }
}
