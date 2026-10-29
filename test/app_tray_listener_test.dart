// 托盘（macOS 是菜单栏图标）的点击：Windows 照原来的行为；macOS 退出过程中不再打开窗口。
// 最小化的窗口两个平台都由 windowManager.show() 先恢复（它自己先问 isMinimized）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/main.dart' show AppTrayListener;
import 'package:tray_manager/tray_manager.dart';

import 'helpers/app_logger_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppLoggerTestIsolation.setUp);
  tearDownAll(AppLoggerTestIsolation.tearDown);

  final calls = <String>[];
  var minimized = false;
  const channels = [
    'window_manager',
    'tray_manager',
    'com.nailauncher/window_control',
  ];

  setUp(() {
    calls.clear();
    minimized = false;
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (call) async {
            if (channel == 'com.nailauncher/window_control') return null;
            calls.add(call.method);
            return call.method == 'isMinimized' ? minimized : null;
          });
    }
  });

  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });

  Future<void> clickAll(AppTrayListener listener) async {
    await listener.onTrayIconMouseDown();
    listener.onTrayIconRightMouseDown();
    await listener.onTrayMenuItemClick(MenuItem(key: 'show', label: 'Show'));
  }

  test('Windows: clicks behave as before, even while quitting', () async {
    await clickAll(AppTrayListener(macOS: false, shuttingDown: () => true));
    expect(calls, [
      'isMinimized',
      'show',
      'focus',
      'popUpContextMenu',
      'isMinimized',
      'show',
      'focus',
    ]);
  });

  test('macOS: clicks are ignored once quitting has started', () async {
    await clickAll(AppTrayListener(macOS: true, shuttingDown: () => true));
    expect(calls, isEmpty);
  });

  for (final macOS in [true, false]) {
    test('${macOS ? 'macOS' : 'Windows'}: show restores a minimized window '
        'first', () async {
      minimized = true;
      await AppTrayListener(
        macOS: macOS,
        shuttingDown: () => false,
      ).onTrayIconMouseDown();
      expect(calls, ['isMinimized', 'restore', 'show', 'focus']);
    });
  }
}
