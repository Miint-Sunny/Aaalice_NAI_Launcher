// macOS 按规范用 ⌘ 当主修饰键，默认快捷键 ctrl+3（本地图库）在 Mac 上是 ⌘3。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/shortcuts/default_shortcuts.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/presentation/providers/shortcuts_provider.dart';
import 'package:nai_launcher/presentation/widgets/shortcuts/shortcut_aware_widget.dart';

class _DefaultConfig extends ShortcutConfigNotifier {
  @override
  Future<ShortcutConfig> build() async => ShortcutConfig.createDefault();
}

Future<void> _pumpGallerySwitch(WidgetTester tester, VoidCallback onHit) async {
  final container = ProviderContainer(
    overrides: [
      shortcutConfigNotifierProvider.overrideWith(_DefaultConfig.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ShortcutAwareWidget(
            contextType: ShortcutContext.global,
            autofocus: true,
            shortcuts: {ShortcutIds.navigateToLocalGallery: onHit},
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('macOS：⌘3 切到本地图库，Control+3 不触发', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      var hits = 0;
      await _pumpGallerySwitch(tester, () => hits++);
      await _chord(tester, LogicalKeyboardKey.metaLeft);
      expect(hits, 1);
      await _chord(tester, LogicalKeyboardKey.controlLeft);
      expect(hits, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows：照旧是 Ctrl+3', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var hits = 0;
      await _pumpGallerySwitch(tester, () => hits++);
      await _chord(tester, LogicalKeyboardKey.controlLeft);
      expect(hits, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
