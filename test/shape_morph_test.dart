import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/widgets/morph_shapes.dart';
import 'package:uessh/widgets/shape_morph_indicator.dart';

void main() {
  test('includes the requested shapes', () {
    final names = morphShapes.map((s) => s.name).toSet();
    expect(names, containsAll(['circle', 'triangle', 'star', 'clover']));
  });

  test('every shape has the same sample layout and fits the unit circle', () {
    for (final s in morphShapes) {
      expect(s.radii.length, sampleCount, reason: s.name);
      for (final r in s.radii) {
        expect(r, inInclusiveRange(0.0, 1.0001), reason: s.name);
        expect(r, greaterThan(0.2), reason: '${s.name} has a hole');
      }
    }
  });

  test('morph endpoints equal the source and target shapes', () {
    final a = morphShapes[0].radii, b = morphShapes[4].radii;
    expect(lerpRadii(a, b, 0), a);
    expect(lerpRadii(a, b, 1), b);
    final mid = lerpRadii(a, b, 0.5);
    for (var i = 0; i < sampleCount; i++) {
      expect(mid[i], closeTo((a[i] + b[i]) / 2, 1e-6));
    }
  });

  testWidgets('indicator keeps animating and changes shape each cycle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: ShapeMorphIndicator(random: math.Random(7))),
      ),
    );
    final cycle =
        ShapeMorphIndicator.morphDuration + ShapeMorphIndicator.holdDuration;

    // Run several full cycles; any exception would fail the test.
    for (var i = 0; i < 12; i++) {
      await tester.pump(cycle ~/ 3);
    }
    expect(find.byType(ShapeMorphIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Removing it must stop the ticker cleanly.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(cycle);
  });
}
