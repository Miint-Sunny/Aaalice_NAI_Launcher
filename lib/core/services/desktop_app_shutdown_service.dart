import 'dart:async';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../database/database_manager.dart';
import '../utils/app_logger.dart';
import 'app_visibility.dart';

/// 桌面应用统一退出入口。
///
/// 更新安装和托盘退出都必须先释放数据库、托盘与窗口资源，避免直接
/// `exit` 留下未刷新的日志或 Windows 文件锁。
class DesktopAppShutdownService {
  DesktopAppShutdownService._();

  static Future<void>? _shutdownFuture;
  // 退出开始后，macOS 上菜单栏图标的点击不再把窗口打开（见 AppTrayListener）
  static bool get isShuttingDown => _shutdownFuture != null;
  static final _cleanups = <Future<void> Function()>{};

  /// Register owned background work that must finish before stores are closed.
  static void Function() registerCleanup(Future<void> Function() cleanup) {
    _cleanups.add(cleanup);
    return () => _cleanups.remove(cleanup);
  }

  static Future<void> prepareBackgroundShutdown() async {
    for (final cleanup in List.of(_cleanups)) {
      try {
        await cleanup();
      } catch (error) {
        AppLogger.w('Background shutdown failed: $error', 'AppShutdown');
      }
    }
  }

  static Future<void> shutdownAndExit(int code) {
    return _shutdownFuture ??= _performShutdown(code);
  }

  static Future<void> _performShutdown(int code) async {
    AppLogger.i('Application shutdown started', 'AppShutdown');

    // macOS：先藏窗口、撤菜单栏图标，再等后台任务、关数据库，退出过程中不留一个卡住的窗口
    // （⌘Q、程序坞「退出」时系统等着应用退出）。Windows 照原来的顺序，最后才撤托盘、关窗口
    if (Platform.isMacOS) {
      AppVisibilitySources.instance.markHidden();
      try {
        await windowManager.hide();
      } catch (error) {
        AppLogger.w(
          'Window hide failed during shutdown: $error',
          'AppShutdown',
        );
      }
      try {
        await trayManager.destroy();
      } catch (error) {
        AppLogger.w('Tray shutdown failed: $error', 'AppShutdown');
      }
    }

    await prepareBackgroundShutdown();

    try {
      await DatabaseManager.instance.dispose();
      AppLogger.i('Database closed successfully', 'AppShutdown');
    } catch (error) {
      AppLogger.w('Database shutdown skipped or failed: $error', 'AppShutdown');
    }

    try {
      await Hive.close();
      AppLogger.i('Hive boxes closed successfully', 'AppShutdown');
    } catch (error) {
      AppLogger.w('Hive shutdown skipped or failed: $error', 'AppShutdown');
    }

    if (Platform.isWindows) {
      try {
        await trayManager.destroy();
      } catch (error) {
        AppLogger.w('Tray shutdown failed: $error', 'AppShutdown');
      }
    }

    // macOS 上从菜单退出（⌘Q）时，下面的 destroy 会让系统立刻结束进程，走不到最后的 flush
    if (Platform.isMacOS) await AppLogger.flush();

    if (Platform.isWindows || Platform.isMacOS) {
      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } catch (error) {
        AppLogger.w('Window shutdown failed: $error', 'AppShutdown');
      }
    }

    AppLogger.i('Application shutdown completed', 'AppShutdown');
    await AppLogger.flush();
    exit(code);
  }
}
