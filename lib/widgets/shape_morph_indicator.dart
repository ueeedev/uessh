import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'morph_shapes.dart';
import '../l10n/l10n.dart';

/// Loading indicator: a vector shape that keeps rotating and seamlessly
/// morphs into a randomly chosen next shape (star, triangle, circle,
/// four-leaf clover, ...).
class ShapeMorphIndicator extends StatefulWidget {
  const ShapeMorphIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.contained = false,
    this.random,
  });

  final double size;

  /// Defaults to the theme's primary color.
  final Color? color;

  /// Draws a soft circular container behind the shape.
  final bool contained;

  /// Injectable for tests.
  final math.Random? random;

  /// How long one shape-to-shape morph takes.
  static const morphDuration = Duration(milliseconds: 650);

  /// Pause on each shape before morphing again.
  static const holdDuration = Duration(milliseconds: 200);

  @override
  State<ShapeMorphIndicator> createState() => _ShapeMorphIndicatorState();
}

class _ShapeMorphIndicatorState extends State<ShapeMorphIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final math.Random _random = widget.random ?? math.Random();
  final _frame = ValueNotifier<_Frame>(const _Frame.empty());
  final _blend = Float32List(sampleCount);

  late int _from = _random.nextInt(morphShapes.length);
  late int _to = _pickNext(_from);
  int _cycle = 0;

  static final _morphMs = ShapeMorphIndicator.morphDuration.inMilliseconds;
  static final _cycleMs =
      _morphMs + ShapeMorphIndicator.holdDuration.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _onTick(Duration.zero);
  }

  int _pickNext(int current) {
    var next = _random.nextInt(morphShapes.length - 1);
    if (next >= current) next++; // never the same shape twice in a row
    return next;
  }

  void _onTick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    final cycle = ms ~/ _cycleMs;
    while (_cycle < cycle) {
      _cycle++;
      _from = _to;
      _to = _pickNext(_from);
    }

    final inCycle = ms % _cycleMs;
    final t = Curves.easeInOutCubic.transform(
      (inCycle / _morphMs).clamp(0.0, 1.0),
    );
    lerpRadii(morphShapes[_from].radii, morphShapes[_to].radii, t, _blend);

    // Steady spin plus an extra quarter turn during each morph, so the
    // shape "whips" into its new form and then keeps turning.
    final steady = ms / 1000 * math.pi; // half a turn per second
    final kick = (_cycle + t) * math.pi / 2;
    _frame.value = _Frame(_blend, steady + kick, ms);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: currentL10n.loading,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _MorphPainter(
            frame: _frame,
            color: widget.color ?? scheme.primary,
            containerColor: widget.contained ? scheme.primaryContainer : null,
          ),
        ),
      ),
    );
  }
}

class _Frame {
  const _Frame(this.radii, this.rotation, this.stamp);
  const _Frame.empty() : radii = null, rotation = 0, stamp = -1;

  final Float32List? radii;
  final double rotation;
  final int stamp;
}

class _MorphPainter extends CustomPainter {
  const _MorphPainter({
    required this.frame,
    required this.color,
    this.containerColor,
  }) : super(repaint: frame);

  final ValueNotifier<_Frame> frame;
  final Color color;
  final Color? containerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radii = frame.value.radii;
    if (radii == null) return;
    final center = size.center(Offset.zero);
    var shapeSize = size.shortestSide;

    if (containerColor != null) {
      canvas.drawCircle(
        center,
        shapeSize / 2,
        Paint()..color = containerColor!,
      );
      shapeSize *= 0.62;
    }
    canvas.drawPath(
      outlinePath(radii, center, shapeSize, rotation: frame.value.rotation),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.color != color || old.containerColor != containerColor;
}
