import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Every shape is stored the same way: its outline radius at [sampleCount]
/// evenly spaced angles around the center (angle 0 = straight up).
/// Because all shapes share that layout, morphing between any two of them
/// is just blending the radii, so the transition is always seamless.
const sampleCount = 240;

class MorphShape {
  MorphShape._(this.name, this.radii);

  final String name;

  /// Radius per sample, scaled so the outline fits a unit circle.
  final Float32List radii;

  /// Outline as a closed vector path centered on [center].
  Path toPath(Offset center, double size, {double rotation = 0}) =>
      outlinePath(radii, center, size, rotation: rotation);

  /// Builds a shape from a polar function `r(angle)`, then rounds sharp
  /// corners with a circular moving average of [smoothing] samples.
  factory MorphShape.polar(
    String name,
    double Function(double angle) radiusAt, {
    int smoothing = 1,
  }) {
    var r = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      r[i] = radiusAt(i / sampleCount * 2 * math.pi);
    }
    for (var pass = 0; pass < 2 && smoothing > 1; pass++) {
      r = _smooth(r, smoothing);
    }
    return MorphShape._(name, _normalize(r));
  }

  /// Regular polygon with a corner pointing up; [flatTop] turns it so an
  /// edge is on top instead (a square rather than a diamond).
  factory MorphShape.polygon(
    String name,
    int sides, {
    int smoothing = 9,
    bool flatTop = false,
  }) {
    final inner = math.cos(math.pi / sides); // edge midpoint radius
    final offset = flatTop ? math.pi / sides : 0.0;
    return MorphShape.polar(
      name,
      (a) => _alternating(a + offset, sides, 1, inner),
      smoothing: smoothing,
    );
  }

  /// Star with [points] tips; [inner] is the valley radius (0–1).
  factory MorphShape.star(
    String name,
    int points,
    double inner, {
    int smoothing = 7,
  }) => MorphShape.polar(
    name,
    (a) => _alternating(a, points, 1, inner),
    smoothing: smoothing,
  );
}

/// Radius along straight edges that alternate between [outer] (at the
/// tips) and [inner] (halfway between tips). Polygons and stars share this.
double _alternating(double a, int n, double outer, double inner) {
  final seg = math.pi / n; // tip → valley angle
  var s = a % (2 * seg);
  if (s > seg) s = 2 * seg - s; // mirror the second half
  // Polar equation of the line through (outer, 0) and (inner, seg).
  return outer *
      inner *
      math.sin(seg) /
      (outer * math.sin(s) + inner * math.sin(seg - s));
}

/// Outline of [n] circles of radius [rho] whose centers sit [d] from the
/// middle, between the axes (so leaves point diagonally).
double _petals(double a, int n, double d, double rho) {
  final step = 2 * math.pi / n;
  // Angle to the nearest circle center.
  final delta = ((a - step / 2) % step + step) % step;
  final dlt = delta > step / 2 ? delta - step : delta;
  final off = d * math.sin(dlt);
  if (off.abs() >= rho) return 0;
  return d * math.cos(dlt) + math.sqrt(rho * rho - off * off);
}

Float32List _smooth(Float32List r, int window) {
  final out = Float32List(r.length);
  final half = window ~/ 2;
  for (var i = 0; i < r.length; i++) {
    var sum = 0.0;
    for (var k = -half; k <= half; k++) {
      sum += r[(i + k) % r.length];
    }
    out[i] = sum / (2 * half + 1);
  }
  return out;
}

/// Scales shapes to a similar visual weight (equal area), but never past
/// the unit circle, so a circle doesn't look huge next to a triangle.
Float32List _normalize(Float32List r) {
  var maxR = 0.0, sumSq = 0.0;
  for (final v in r) {
    maxR = math.max(maxR, v);
    sumSq += v * v;
  }
  final rms = math.sqrt(sumSq / r.length);
  final scale = math.min(0.86 / rms, 1 / maxR);
  return Float32List.fromList([for (final v in r) v * scale]);
}

/// Shared by shapes and in-between frames.
Path outlinePath(
  Float32List radii,
  Offset center,
  double size, {
  double rotation = 0,
}) {
  final path = Path();
  final half = size / 2;
  for (var i = 0; i < radii.length; i++) {
    final a = i / radii.length * 2 * math.pi + rotation;
    final p = center + Offset(math.sin(a), -math.cos(a)) * (radii[i] * half);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// Blends two outlines; [t] = 0 gives [a], 1 gives [b].
Float32List lerpRadii(
  Float32List a,
  Float32List b,
  double t, [
  Float32List? out,
]) {
  final r = out ?? Float32List(a.length);
  for (var i = 0; i < a.length; i++) {
    r[i] = a[i] + (b[i] - a[i]) * t;
  }
  return r;
}

/// The shapes the loading indicator picks from.
final morphShapes = <MorphShape>[
  MorphShape.polar('circle', (_) => 1),
  MorphShape.polygon('triangle', 3, smoothing: 15),
  MorphShape.polygon('square', 4, smoothing: 13, flatTop: true),
  MorphShape.polygon('pentagon', 5, smoothing: 11),
  MorphShape.star('star', 5, 0.5, smoothing: 7),
  MorphShape.star('burst', 12, 0.78, smoothing: 5),
  // Four-leaf clover: four round leaves on the diagonals.
  MorphShape.polar('clover', (a) => _petals(a, 4, 0.56, 0.44), smoothing: 3),
  // Scalloped "cookie" edge, like Material 3 Expressive shapes.
  MorphShape.polar('cookie', (a) => 0.86 + 0.14 * math.cos(9 * a)),
  // Soft flower with 6 rounded petals.
  MorphShape.polar(
    'flower',
    (a) => 0.7 + 0.3 * math.pow(math.cos(3 * a).abs(), 0.8),
    smoothing: 5,
  ),
];
