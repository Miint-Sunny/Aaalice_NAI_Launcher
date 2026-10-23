import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/utils/selection_modifiers.dart';

HardwareKeyboard _holding(LogicalKeyboardKey logical, PhysicalKeyboardKey key) {
  final keyboard = HardwareKeyboard();
  keyboard.handleKeyEvent(
    KeyDownEvent(
      physicalKey: key,
      logicalKey: logical,
      timeStamp: Duration.zero,
    ),
  );
  return keyboard;
}

/// 按住 [modifier] 按下鼠标，先松开修饰键再抬起鼠标键。
Future<void> _clickReleasingModifierFirst(
  WidgetTester tester,
  LogicalKeyboardKey? modifier,
) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  final gesture = await tester.startGesture(const Offset(10, 10));
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
  await gesture.up();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  final control = _holding(
    LogicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlLeft,
  );
  final command = _holding(
    LogicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaLeft,
  );

  test('macOS：只认 ⌘，Control 不算', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isSelectionModifierPressed(keyboard: command), isTrue);
    expect(isSelectionModifierPressed(keyboard: control), isFalse);
  });

  test('Windows：Ctrl 和 Meta 都算（不变）', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(isSelectionModifierPressed(keyboard: control), isTrue);
    expect(isSelectionModifierPressed(keyboard: command), isTrue);
    expect(isSelectionModifierPressed(keyboard: HardwareKeyboard()), isFalse);
  });

  group('PointerDownModifiers', () {
    setUp(PointerDownModifiers.ensureInstalled);

    testWidgets('macOS：记下按下时的 ⌘ 和 ⇧，修饰键先松开也还在', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());

      await _clickReleasingModifierFirst(tester, LogicalKeyboardKey.metaLeft);
      expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
      expect(PointerDownModifiers.selection, isTrue);
      expect(PointerDownModifiers.shift, isFalse);

      await _clickReleasingModifierFirst(tester, null);
      expect(PointerDownModifiers.selection, isFalse);

      // Mac 上 Control+点击是右键的意思，不算多选
      await _clickReleasingModifierFirst(
        tester,
        LogicalKeyboardKey.controlLeft,
      );
      expect(PointerDownModifiers.selection, isFalse);

      await _clickReleasingModifierFirst(tester, LogicalKeyboardKey.shiftLeft);
      expect(PointerDownModifiers.selection, isFalse);
      expect(PointerDownModifiers.shift, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Windows：Ctrl 算多选修饰键', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());

      await _clickReleasingModifierFirst(
        tester,
        LogicalKeyboardKey.controlLeft,
      );
      expect(PointerDownModifiers.selection, isTrue);

      await _clickReleasingModifierFirst(tester, null);
      expect(PointerDownModifiers.selection, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
