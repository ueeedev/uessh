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

  // With "keep running in background", closing the window only hides it, and
  // Cmd+M minimizes it to the Dock. Clicking the Dock icon must both
  // deminiaturize and show the main window even if auxiliary windows (such as
  // the menu bar status item) make AppKit report hasVisibleWindows == true.
  // Note: FlutterAppDelegate does not implement applicationShouldHandleReopen,
  // so calling super would throw an unrecognized selector exception at runtime.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    let mainWindows = sender.windows.compactMap { $0 as? MainFlutterWindow }
    let targets: [NSWindow] = mainWindows.isEmpty
      ? [mainFlutterWindow].compactMap { $0 }
      : mainWindows
    let hasVisibleMain = targets.contains { $0.isVisible && !$0.isMiniaturized }
    if !flag || !hasVisibleMain {
      for window in targets {
        if window.isMiniaturized {
          window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
      }
      sender.activate(ignoringOtherApps: true)
      return false
    }
    return true
  }
}
