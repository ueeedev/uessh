import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Where the middle of the window buttons (traffic lights) goes, in
  /// points from the top: the middle of the app's tabs (a 40pt strip with
  /// 32pt tabs at its bottom; see tabStripHeight in terminal_page.dart).
  private let trafficLightCenterY: CGFloat = 24
  /// Left edge of the close button.
  private let trafficLightX: CGFloat = 16

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // The title bar is hidden and the app draws there (tabs sit in it).
    // The invisible system title bar would still move the window when
    // something in that strip is dragged - a tab, for example - so the
    // window doesn't move by itself; the app starts window drags only
    // from its own empty title-bar areas (window_manager startDragging,
    // which ends up in performDrag below).
    isMovable = false

    // AppKit puts the window buttons back after these; move them again.
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didBecomeMainNotification,
    ] {
      NotificationCenter.default.addObserver(
        forName: name, object: self, queue: .main
      ) { [weak self] _ in self?.placeTrafficLights() }
    }
    DispatchQueue.main.async { [weak self] in self?.placeTrafficLights() }
  }

  /// Centers the close / minimize / zoom buttons on the app's tabs
  /// instead of the default spot near the top edge.
  func placeTrafficLights() {
    guard
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let container = close.superview?.superview
    else { return }
    // No moving in full screen: the system shows its own title bar there.
    if styleMask.contains(.fullScreen) { return }
    let buttonHeight = close.frame.height
    let spacing = mini.frame.minX - close.frame.maxX
    let height = trafficLightCenterY * 2
    var bar = container.frame
    bar.size.height = height
    bar.origin.y = frame.height - height
    container.frame = bar
    var x = trafficLightX
    for button in [close, mini, zoom] {
      button.setFrameOrigin(NSPoint(x: x, y: (height - buttonHeight) / 2))
      x += button.frame.width + spacing
    }
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(frameRect, display: flag)
    placeTrafficLights()
  }

  override func performDrag(with event: NSEvent) {
    isMovable = true
    super.performDrag(with: event)
    // Back to not movable once the drag is over.
    DispatchQueue.main.async { [weak self] in
      if NSEvent.pressedMouseButtons == 0 { self?.isMovable = false }
    }
  }

  override func sendEvent(_ event: NSEvent) {
    // In case the drag loop returned while the button was still down.
    if event.type == .leftMouseUp && isMovable { isMovable = false }
    super.sendEvent(event)
  }
}
