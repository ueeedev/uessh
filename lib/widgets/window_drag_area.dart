import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// On macOS the system title bar is hidden and the app draws to the top of
/// the window, so these are the places that act as the title bar.
bool get usesCustomTitleBar => defaultTargetPlatform == TargetPlatform.macOS;

/// Vertical room kept free for the macOS traffic-light buttons.
double get trafficLightInset => usesCustomTitleBar ? 28 : 0;

/// Makes the empty parts of [child] behave like a title bar on macOS:
/// drag to move the window, double-click to zoom.
///
/// The drag surface sits *behind* [child], so buttons and fields inside
/// get their clicks directly. (Wrapping them in a double-tap detector
/// would delay every single click while it waits for a possible second.)
/// Elsewhere it just returns [child].
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!usesCustomTitleBar) return child;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('window-drag-surface'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
        ),
        child,
      ],
    );
  }
}
