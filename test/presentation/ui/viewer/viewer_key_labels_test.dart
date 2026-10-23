// 查看器的快捷键键帽：Windows 写 Ctrl R，macOS 用 Mac 符号（配置里的主修饰键在 Mac 上是 ⌘）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_contract.dart';
import 'package:nai_launcher/presentation/ui/viewer/viewer_format.dart';
import 'package:nai_launcher/presentation/wiring/image_viewer_mapping.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS：⌘ 而不是 Meta，⌃⌥⇧⌘ 按 Mac 的顺序，特殊键用符号', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final keys = viewerKeysOf(ShortcutConfig.createDefault());
    expect(viewerKeyLabels(keys[ViewerCommand.reuse]!.single), ['⌘', 'R']);
    expect(viewerKeyLabels(keys[ViewerCommand.delete]!.single), ['⌘', '⌫']);
    expect(viewerKeyLabels(keys[ViewerCommand.fullscreen]!.single), [
      '⌃',
      '⌘',
      'F',
    ]);
    expect(viewerKeyLabels(keys[ViewerCommand.close]!.single), ['⎋']);
    expect(viewerKeyText(keys[ViewerCommand.reuse]!.single), '⌘R');
    expect(
      viewerKeyLabels(
        const SingleActivator(LogicalKeyboardKey.slash, shift: true),
      ),
      ['?'],
    );
  });

  test('Windows：照旧 Ctrl R、Delete', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final keys = viewerKeysOf(ShortcutConfig.createDefault());
    expect(viewerKeyLabels(keys[ViewerCommand.reuse]!.single), ['Ctrl', 'R']);
    expect(viewerKeyLabels(keys[ViewerCommand.delete]!.single), ['Delete']);
    expect(viewerKeyText(keys[ViewerCommand.reuse]!.single), 'Ctrl R');
  });
}
