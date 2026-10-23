// 主修饰键：macOS 上是 ⌘（不带 Control），其他平台是 Ctrl；macOS 上按着 ⌘ / Control 的字母键不当裸键。
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/keyboard_modifier_utils.dart';
import 'package:nai_launcher/core/utils/primary_activator.dart';

/// 按住 [modifiers] 时读一次 [read]。
Future<bool> _while(
  WidgetTester t,
  List<LogicalKeyboardKey> modifiers,
  bool Function() read,
) async {
  for (final m in modifiers) {
    await t.sendKeyDownEvent(m);
  }
  final value = read();
  for (final m in modifiers.reversed) {
    await t.sendKeyUpEvent(m);
  }
  return value;
}

/// CallbackShortcuts 绑 `PrimaryActivator(S)`，按 [modifiers] + S，返回触发次数。
Future<int> _hits(WidgetTester t, List<LogicalKeyboardKey> modifiers) async {
  var hits = 0;
  await t.pumpWidget(
    CallbackShortcuts(
      bindings: {const PrimaryActivator(LogicalKeyboardKey.keyS): () => hits++},
      child: const Focus(autofocus: true, child: SizedBox()),
    ),
  );
  await t.pump();
  for (final m in modifiers) {
    await t.sendKeyDownEvent(m);
  }
  await t.sendKeyEvent(LogicalKeyboardKey.keyS);
  for (final m in modifiers.reversed) {
    await t.sendKeyUpEvent(m);
  }
  return hits;
}

const _cmd = LogicalKeyboardKey.metaLeft;
const _control = LogicalKeyboardKey.controlLeft;

void main() {
  testWidgets('macOS：⌘ 是主修饰键，⌃⌘ 不算；按着 ⌘ 或 Control 是组合键', (t) async {
    expect(await _while(t, [_cmd], isPrimaryShortcutModifierPressed), true);
    expect(
      await _while(t, [_control], isPrimaryShortcutModifierPressed),
      false,
    );
    expect(
      await _while(t, [_control, _cmd], isPrimaryShortcutModifierPressed),
      false,
    );
    expect(await _while(t, [_cmd], isMacChordModifierPressed), true);
    expect(await _while(t, [_control], isMacChordModifierPressed), true);
    expect(await _while(t, [], isMacChordModifierPressed), false);
    expect(await _hits(t, [_cmd]), 1);
    expect(await _hits(t, [_control]), 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Windows：照旧是 Ctrl，没有 Mac 的组合键判断', (t) async {
    expect(await _while(t, [_control], isPrimaryShortcutModifierPressed), true);
    expect(await _while(t, [_cmd], isPrimaryShortcutModifierPressed), false);
    expect(await _while(t, [_control], isMacChordModifierPressed), false);
    expect(await _while(t, [_cmd], isMacChordModifierPressed), false);
    expect(await _hits(t, [_control]), 1);
    expect(await _hits(t, [_cmd]), 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
