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

    super.awakeFromNib()
  }
}
