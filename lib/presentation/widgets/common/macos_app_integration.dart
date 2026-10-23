import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/services/desktop_app_shutdown_service.dart';

/// Mac 原生菜单和 Dart 之间的通道：应用菜单「设置…」（⌘,）点了要打开设置页。
/// 原生一侧在 macos/Runner/AppDelegate.swift 的 showSettings(_:)。
const macOSAppMenuChannel = MethodChannel('com.nailauncher/app_menu');

/// Mac 系统集成：
/// - 应用菜单「设置…」→ [onOpenSettings]
/// - 系统发来的退出请求（菜单「退出」⌘Q、程序坞「退出」、注销关机）走
///   [onExitRequested]，默认是 W.O.F 托盘「退出」用的正规关闭流程（先关数据库、Hive 再退）。
///   原来 Dart 没接这个请求，从菜单退出时不关数据库。
///
/// 只在 macOS 上生效，其他平台原样返回 [child]。
class MacOSAppIntegration extends StatefulWidget {
  const MacOSAppIntegration({
    super.key,
    required this.onOpenSettings,
    this.onExitRequested = _shutdown,
    required this.child,
  });

  final VoidCallback onOpenSettings;
  final Future<void> Function() onExitRequested;
  final Widget child;

  static Future<void> _shutdown() =>
      DesktopAppShutdownService.shutdownAndExit(0);

  @override
  State<MacOSAppIntegration> createState() => _MacOSAppIntegrationState();
}

class _MacOSAppIntegrationState extends State<MacOSAppIntegration> {
  // 启动时这个组件会先后建两份（启动页、主界面），旧的 dispose 晚于新的 initState。
  // 所以通道处理函数是静态的、销毁时不清掉，消息转给当前在树上的那一份。
  static _MacOSAppIntegrationState? _current;

  AppLifecycleListener? _lifecycle;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (!_isMac) return;
    _current = this;
    macOSAppMenuChannel.setMethodCallHandler(_dispatchMenuCall);
    _lifecycle = AppLifecycleListener(onExitRequested: _handleExitRequest);
  }

  static Future<Object?> _dispatchMenuCall(MethodCall call) async {
    final state = _current;
    if (state == null || !state.mounted) return null;
    if (call.method == 'openSettings') state.widget.onOpenSettings();
    return null;
  }

  Future<AppExitResponse> _handleExitRequest() async {
    // 关闭流程最后自己 exit()；万一返回了，也照常退出
    await widget.onExitRequested();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    if (identical(_current, this)) _current = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
