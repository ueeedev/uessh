import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// macOS and Windows hide the system title bar and the app draws to the
/// top of the window, so some places act as the title bar instead.
bool get usesCustomTitleBar =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

/// Vertical room kept free for the macOS traffic-light buttons.
double get trafficLightInset =>
    defaultTargetPlatform == TargetPlatform.macOS ? 28 : 0;

/// Size of one Windows caption button (minimize / maximize / close).
const captionButtonSize = Size(46, 32);

/// Height of the band the Windows caption buttons take at the top right.
double get captionBarHeight => _isWindows ? captionButtonSize.height : 0;

/// Width kept free at the right of top bars for the Windows caption buttons.
double get captionButtonsInset => _isWindows ? captionButtonSize.width * 3 : 0;

/// Makes the empty parts of [child] behave like a title bar:
/// drag to move the window, double-click to maximize.
///
/// The drag surface sits *behind* [child], so buttons and fields inside
/// get their clicks directly. (Wrapping them in a double-tap detector
/// would delay every single click while it waits for a possible second.)
/// Where the system title bar is kept it just returns [child].
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
            onDoubleTap: toggleMaximize,
          ),
        ),
        child,
      ],
    );
  }
}

/// Maximizes the window, or restores it if it already is.
Future<void> toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Title-bar behaviour for an area whose empty parts are covered by other
/// widgets (e.g. the tab strip's list): drag on a spot where [isBlank] is
/// true moves the window, double-click there maximizes / restores it.
///
/// Works on raw pointer events, outside the gesture arena, so the
/// widgets inside keep their taps and drags with no delay.
class TitleBarListener extends StatefulWidget {
  const TitleBarListener({
    super.key,
    required this.isBlank,
    required this.child,
  });

  final bool Function(Offset local) isBlank;
  final Widget child;

  @override
  State<TitleBarListener> createState() => _TitleBarListenerState();
}

class _TitleBarListenerState extends State<TitleBarListener> {
  Offset? _down;
  bool _dragging = false;
  Duration? _lastUp;
  Offset? _lastUpAt;

  static const _slop = 4.0;
  static const _doubleClick = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    if (!usesCustomTitleBar) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _down = e.buttons == kPrimaryButton && widget.isBlank(e.localPosition)
            ? e.position
            : null;
        _dragging = false;
      },
      onPointerMove: (e) {
        final down = _down;
        if (down == null || _dragging) return;
        if ((e.position - down).distance > _slop) {
          _dragging = true;
          _lastUp = null;
          windowManager.startDragging();
        }
      },
      onPointerUp: (e) {
        final down = _down;
        _down = null;
        if (down == null || _dragging) return;
        final last = _lastUp, lastAt = _lastUpAt;
        if (last != null &&
            lastAt != null &&
            e.timeStamp - last < _doubleClick &&
            (e.position - lastAt).distance < 8) {
          _lastUp = null;
          toggleMaximize();
        } else {
          _lastUp = e.timeStamp;
          _lastUpAt = e.position;
        }
      },
      onPointerCancel: (_) => _down = null,
      child: widget.child,
    );
  }
}

/// Puts the Windows minimize / maximize / close buttons over the top right
/// corner of [child]. Elsewhere it just returns [child].
class WindowCaptionOverlay extends StatelessWidget {
  const WindowCaptionOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_isWindows) return child;
    return Stack(
      children: [
        child,
        const Positioned(top: 0, right: 0, child: WindowCaptionButtons()),
      ],
    );
  }
}

enum _Caption { minimize, maximize, restore, close }

/// Windows-style caption buttons drawn in the app's colors.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _sync();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final m = await windowManager.isMaximized();
      if (mounted && m != _maximized) setState(() => _maximized = m);
    } catch (_) {
      // No window plugin (tests).
    }
  }

  @override
  void onWindowMaximize() => _sync();
  @override
  void onWindowUnmaximize() => _sync();
  @override
  void onWindowRestore() => _sync();
  @override
  void onWindowResized() => _sync();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('window-caption-buttons'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          kind: _Caption.minimize,
          onPressed: () => windowManager.minimize(),
        ),
        _CaptionButton(
          kind: _maximized ? _Caption.restore : _Caption.maximize,
          onPressed: toggleMaximize,
        ),
        _CaptionButton(
          kind: _Caption.close,
          // Goes through the normal close path, so "keep running in
          // the background" can hide the window instead.
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.kind, required this.onPressed});

  final _Caption kind;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _down = false;

  static const _closeRed = Color(0xFFC42B1C);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isClose = widget.kind == _Caption.close;
    final Color bg;
    if (isClose && (_hover || _down)) {
      bg = _down ? _closeRed.withValues(alpha: 0.85) : _closeRed;
    } else if (_down) {
      bg = scheme.onSurface.withValues(alpha: 0.12);
    } else if (_hover) {
      bg = scheme.onSurface.withValues(alpha: 0.08);
    } else {
      bg = Colors.transparent;
    }
    final fg = isClose && (_hover || _down) ? Colors.white : scheme.onSurface;

    return Semantics(
      button: true,
      label: widget.kind.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          key: ValueKey('caption-${widget.kind.name}'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTap: () {
            setState(() => _down = false);
            widget.onPressed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: captionButtonSize.width,
            height: captionButtonSize.height,
            color: bg,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _CaptionGlyph(widget.kind, fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin 10px glyphs like the Windows 11 caption buttons.
class _CaptionGlyph extends CustomPainter {
  _CaptionGlyph(this.kind, this.color);

  final _Caption kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width;
    switch (kind) {
      case _Caption.minimize:
        canvas.drawLine(Offset(0, w / 2), Offset(w, w / 2), p);
      case _Caption.maximize:
        canvas.drawRRect(
          RRect.fromLTRBR(
            0.5,
            0.5,
            w - 0.5,
            w - 0.5,
            const Radius.circular(1.5),
          ),
          p,
        );
      case _Caption.restore:
        canvas.drawRRect(
          RRect.fromLTRBR(
            0.5,
            2.5,
            w - 2.5,
            w - 0.5,
            const Radius.circular(1.5),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 0.5)
            ..lineTo(w - 1.5, 0.5)
            ..quadraticBezierTo(w - 0.5, 0.5, w - 0.5, 1.5)
            ..lineTo(w - 0.5, w - 2.5),
          p,
        );
      case _Caption.close:
        canvas.drawLine(Offset.zero, Offset(w, w), p);
        canvas.drawLine(Offset(w, 0), Offset(0, w), p);
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyph old) =>
      old.kind != kind || old.color != color;
}
