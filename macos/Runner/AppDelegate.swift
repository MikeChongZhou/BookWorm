import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  @objc func showBookWormAbout(_ sender: Any?) {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    FlutterMethodChannel(name: "bookworm/app_menu", binaryMessenger: controller.engine.binaryMessenger)
      .invokeMethod("showAbout", arguments: nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
