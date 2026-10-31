import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "W.O.F NAI Studio"

    RegisterGeneratedPlugins(registry: flutterViewController)
    // 应用菜单「设置…」用的通道（见 AppDelegate.showSettings）
    (NSApp.delegate as? AppDelegate)?.appMenuChannel = FlutterMethodChannel(
      name: "com.nailauncher/app_menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    registerSystemFontsChannel(flutterViewController.engine.binaryMessenger)
    registerVisibilityChannel(flutterViewController.engine.binaryMessenger)
    registerAccessibilityChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  // 系统「减少动态效果」「降低透明度」：Flutter 的 macOS 引擎不读，这里读了、
  // 变了再告诉 Dart（lib/core/services/mac_display_options.dart）
  private var accessibilityChannel: FlutterMethodChannel?

  private func registerAccessibilityChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.nailauncher/accessibility", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getDisplayOptions" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(MainFlutterWindow.displayOptions())
    }
    accessibilityChannel = channel
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(displayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  static func displayOptions() -> [String: Bool] {
    let workspace = NSWorkspace.shared
    return [
      "reduceMotion": workspace.accessibilityDisplayShouldReduceMotion,
      "reduceTransparency": workspace.accessibilityDisplayShouldReduceTransparency,
    ]
  }

  @objc private func displayOptionsDidChange(_ notification: Notification) {
    accessibilityChannel?.invokeMethod(
      "displayOptionsChanged", arguments: MainFlutterWindow.displayOptions())
  }

  // 窗口看不看得见：最小化、藏到菜单栏、被别的窗口完全挡住、在别的桌面时都看不见。
  // Dart 一侧据此停掉动画（lib/core/services/app_visibility.dart）
  private var visibilityChannel: FlutterMethodChannel?

  private func registerVisibilityChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.nailauncher/window_visibility", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "isVisible" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.isOnScreen ?? true)
    }
    visibilityChannel = channel
    NotificationCenter.default.addObserver(
      self, selector: #selector(occlusionStateDidChange(_:)),
      name: NSWindow.didChangeOcclusionStateNotification, object: self)
  }

  private var isOnScreen: Bool { occlusionState.contains(.visible) }

  @objc private func occlusionStateDidChange(_ notification: Notification) {
    visibilityChannel?.invokeMethod("visibilityChanged", arguments: isOnScreen)
  }

  // 系统字体列表，和 Windows runner 同一个通道、同样返回字族名列表
  // （Dart 一侧见 lib/core/services/system_font_service.dart）
  private func registerSystemFontsChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.nailauncher/system_fonts", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "getSystemFonts" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(MainFlutterWindow.systemFontFamilies())
    }
  }

  // 去掉以「.」开头的系统内部字族（例如 .AppleSystemUIFont），按名字选不到，
  // 和 Windows 跳过以「@」开头的竖排字体一样
  static func systemFontFamilies() -> [String] {
    let families = NSFontManager.shared.availableFontFamilies.filter {
      !$0.isEmpty && !$0.hasPrefix(".")
    }
    return Array(Set(families)).sorted()
  }
}
