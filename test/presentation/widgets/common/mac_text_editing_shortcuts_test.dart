// macOS 输入框里 ⌘Y 也能重做（系统自带的是 ⇧⌘Z）；焦点不在输入框时不拦 ⌘Y；Windows 不变。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/mac_text_editing_shortcuts.dart';

/// 输入框里先后输入「a」「ab」，留下两步撤销记录
Future<TextEditingController> _editor(
  WidgetTester tester, {
  FocusNode? elsewhere,
}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MacTextEditingShortcuts(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            TextField(controller: controller),
            Focus(
              focusNode: elsewhere,
              child: const SizedBox(width: 10, height: 10),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextField));
  await tester.pump();
  // 撤销记录会合并很短时间里的改动，两次输入之间等一会儿
  await tester.enterText(find.byType(TextField), 'a');
  await tester.pump(const Duration(seconds: 1));
  await tester.enterText(find.byType(TextField), 'ab');
  await tester.pump(const Duration(seconds: 1));
  return controller;
}

Future<void> _press(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pump();
}

void main() {
  testWidgets('macOS：输入框里 ⇧⌘Z 和 ⌘Y 都能重做', (tester) async {
    final controller = await _editor(tester);
    await _press(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyZ);
    expect(controller.text, 'a');
    await _press(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyY);
    expect(controller.text, 'ab');
    await _press(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyZ);
    expect(controller.text, 'a');
    await _press(tester, [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyZ);
    expect(controller.text, 'ab');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('macOS：焦点不在输入框里时不拦 ⌘Y，按键接着往外传（图库的 ⌘Y 等）', (tester) async {
    final elsewhere = FocusNode();
    addTearDown(elsewhere.dispose);
    await _editor(tester, elsewhere: elsewhere);
    elsewhere.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyY), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Windows：不变，不加 Win+Y', (tester) async {
    final controller = await _editor(tester);
    await _press(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.keyZ);
    expect(controller.text, 'a');
    await _press(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyY);
    expect(controller.text, 'a');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
