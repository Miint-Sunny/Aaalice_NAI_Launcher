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

    super.awakeFromNib()
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
