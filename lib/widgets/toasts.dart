import 'dart:async';

import 'package:flutter/material.dart';

/// How a notice looks: plain, done, or something went wrong.
enum ToastKind { info, success, error }

class ToastEntry {
  ToastEntry({
    required this.id,
    required this.message,
    required this.kind,
    required this.duration,
  });

  final String id;
  final String message;
  final ToastKind kind;

  /// Shown this long (while the pointer isn't on it); null: until closed
  /// or replaced.
  final Duration? duration;

  /// Playing its exit animation; removed afterwards.
  bool leaving = false;
}

/// The notices shown at the top right of the window ([ToastLayer]).
class Toasts extends ChangeNotifier {
  final _entries = <ToastEntry>[];
  int _next = 0;

  /// At most this many at once; older ones leave first.
  static const maxVisible = 4;

  List<ToastEntry> get entries => List.unmodifiable(_entries);

  /// Shows [message]. Passing the [id] of a notice still shown replaces it
  /// in place (e.g. "downloading…" becoming "downloaded"). Returns the id.
  String show(
    String message, {
    ToastKind kind = ToastKind.info,
    Duration? duration = const Duration(seconds: 4),
    String? id,
  }) {
    final key = id ?? 'toast-${_next++}';
    final entry = ToastEntry(
      id: key,
      message: message,
      kind: kind,
      duration: duration,
    );
    final at = _entries.indexWhere((e) => e.id == key && !e.leaving);
    if (at >= 0) {
      _entries[at] = entry;
    } else {
      _entries.add(entry);
      final shown = _entries.where((e) => !e.leaving).toList();
      final extra = shown.length - maxVisible;
      for (final old in shown.take(extra < 0 ? 0 : extra)) {
        old.leaving = true;
      }
    }
    notifyListeners();
    return key;
  }

  /// Starts [id]'s exit animation.
  void dismiss(String id) {
    for (final e in _entries) {
      if (e.id == id) e.leaving = true;
    }
    notifyListeners();
  }

  void _remove(ToastEntry entry) {
    if (_entries.remove(entry)) notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// The app's notices.
final toasts = Toasts();

/// Shows a notice at the top right of the window.
String showToast(
  String message, {
  ToastKind kind = ToastKind.info,
  Duration? duration = const Duration(seconds: 4),
  String? id,
}) => toasts.show(message, kind: kind, duration: duration, id: id);

/// Lays the notices over [child], top right, below the tab strip.
/// [header] (e.g. upload progress) sits above them.
class ToastLayer extends StatefulWidget {
  const ToastLayer({super.key, required this.child, this.header});

  final Widget child;
  final Widget? header;

  /// Below the 40 pt tab strip (and the Windows caption buttons in it).
  static const top = 48.0;

  @override
  State<ToastLayer> createState() => _ToastLayerState();
}

class _ToastLayerState extends State<ToastLayer> {
  @override
  void initState() {
    super.initState();
    // A fresh app starts without old notices.
    toasts.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: ToastLayer.top,
          right: 16,
          child: ListenableBuilder(
            listenable: toasts,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.header != null)
                  AnimatedSwitcher(
                    duration: _ToastCardState.enter,
                    reverseDuration: _ToastCardState.exit,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topRight,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) =>
                        _transition(animation, child),
                    child: widget.header,
                  ),
                for (final e in toasts.entries)
                  _ToastCard(key: ValueKey(e), entry: e),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Slides in from the right while fading in, and makes room by growing;
/// the reverse on the way out.
Widget _transition(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return SizeTransition(
    sizeFactor: curved,
    alignment: Alignment.topRight,
    child: FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.35, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
  );
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.entry});

  final ToastEntry entry;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  static const enter = Duration(milliseconds: 320);
  static const exit = Duration(milliseconds: 220);

  late final _controller = AnimationController(
    vsync: this,
    duration: enter,
    reverseDuration: exit,
  );
  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _startTimer();
  }

  @override
  void didUpdateWidget(_ToastCard old) {
    super.didUpdateWidget(old);
    if (widget.entry.leaving) _leave();
  }

  void _startTimer() {
    _timer?.cancel();
    final d = widget.entry.duration;
    if (d == null || _hovered) return;
    _timer = Timer(d, () => toasts.dismiss(widget.entry.id));
  }

  Future<void> _leave() async {
    _timer?.cancel();
    if (_controller.status == AnimationStatus.reverse) return;
    await _controller.reverse();
    toasts._remove(widget.entry);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = widget.entry;
    final (icon, iconColor, bg, fg) = switch (e.kind) {
      ToastKind.info => (
        Icons.info_outline,
        scheme.primary,
        scheme.surfaceContainerHigh,
        scheme.onSurface,
      ),
      ToastKind.success => (
        Icons.check_circle_outline,
        scheme.primary,
        scheme.surfaceContainerHigh,
        scheme.onSurface,
      ),
      ToastKind.error => (
        Icons.error_outline,
        scheme.onErrorContainer,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    return _transition(
      _controller,
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MouseRegion(
          // Stays while the pointer is on it.
          onEnter: (_) {
            _hovered = true;
            _timer?.cancel();
          },
          onExit: (_) {
            _hovered = false;
            if (!e.leaving) _startTimer();
          },
          child: Material(
            key: ValueKey('toast-${e.id}'),
            elevation: 3,
            color: bg,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          e.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: fg,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // No tooltip: this layer is above the app's Overlay.
                    IconButton(
                      key: ValueKey('toast-close-${e.id}'),
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      color: fg,
                      icon: const Icon(Icons.close),
                      onPressed: () => toasts.dismiss(e.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
