import 'package:flutter/material.dart';

/// Like [IndexedStack] (every child stays alive and keeps its state), but
/// switching [index] plays the Material "fade through" transition: the old
/// page fades out, then the new one fades in while scaling up slightly.
/// Hidden pages are offstage with tickers paused.
class FadeThroughIndexedStack extends StatefulWidget {
  const FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  int? _previous;

  // Outgoing page: gone in the first 35% of the transition.
  late final _fadeOut = Tween<double>(begin: 1, end: 0).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    ),
  );
  // Incoming page: fades and scales in over the rest.
  late final _inCurve = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
  );
  late final _scaleIn = Tween<double>(begin: 0.94, end: 1).animate(_inCurve);

  static const _still = AlwaysStoppedAnimation<double>(1);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) setState(() => _previous = null);
    });
  }

  @override
  void didUpdateWidget(FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    _controller.duration = widget.duration;
    if (old.index != widget.index) {
      _previous = old.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _inCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animating = _previous != null && _controller.isAnimating;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // Same wrapper structure for every child in every state, so no
          // page ever loses its state when it's shown or hidden.
          // Prefer the child's own key so reordering (e.g. closing a
          // terminal tab) keeps each page's state with the right page.
          KeyedSubtree(
            key: widget.children[i].key ?? ValueKey(i),
            child: _wrap(
              i,
              current: i == widget.index,
              outgoing: animating && i == _previous,
            ),
          ),
      ],
    );
  }

  Widget _wrap(int i, {required bool current, required bool outgoing}) {
    final visible = current || outgoing;
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !current,
          child: FadeTransition(
            opacity: outgoing ? _fadeOut : (current ? _inCurve : _still),
            child: ScaleTransition(
              scale: current ? _scaleIn : _still,
              child: widget.children[i],
            ),
          ),
        ),
      ),
    );
  }
}
