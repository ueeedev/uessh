import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Closing the window never quits on its own: the app decides (Dart
  // BackgroundMode) whether to hide it or quit, following the "keep
  // running in background" setting.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // With "keep running in background", closing the window only hides it;
  // clicking the Dock icon shows it again.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // Keep Flutter's own handling (it forwards to plugins), then show ours.
    _ = super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(nil)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }
}
