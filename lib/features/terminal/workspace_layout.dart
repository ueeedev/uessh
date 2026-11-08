import 'dart:ui' show Offset, Rect;

/// How panes inside a split are arranged.
enum SplitAxis {
  /// Side by side (a vertical divider between them).
  row,

  /// Stacked (a horizontal divider between them).
  column,
}

/// Where a pane goes relative to another one.
enum DropSide {
  left,
  right,
  top,
  bottom,

  /// Take the other pane's place (swap).
  center;

  SplitAxis get axis =>
      this == left || this == right ? SplitAxis.row : SplitAxis.column;

  /// The new pane comes before the target (left of / above it).
  bool get before => this == left || this == top;
}

/// Direction for moving focus between panes.
enum PaneDirection { left, right, up, down }

/// A workspace layout: a tree of splits with terminal panes as leaves.
/// Immutable; every operation returns a new tree, normalized so that
/// splits have at least two children, no split directly holds another
/// split of the same axis, and weights add up to 1.
sealed class LayoutNode {
  const LayoutNode();

  /// Session ids of the panes, left-to-right / top-to-bottom.
  List<String> get panes;

  bool contains(String id) => panes.contains(id);
}

class PaneNode extends LayoutNode {
  const PaneNode(this.sessionId);

  final String sessionId;

  @override
  List<String> get panes => [sessionId];

  @override
  bool operator ==(Object other) =>
      other is PaneNode && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;

  @override
  String toString() => sessionId;
}

class SplitNode extends LayoutNode {
  SplitNode(this.axis, this.children, [List<double>? weights])
    : weights = weights ?? List.filled(children.length, 1 / children.length),
      assert(children.length >= 2);

  final SplitAxis axis;
  final List<LayoutNode> children;

  /// Share of the space for each child; adds up to 1.
  final List<double> weights;

  @override
  List<String> get panes => [for (final c in children) ...c.panes];

  @override
  bool operator ==(Object other) =>
      other is SplitNode &&
      other.axis == axis &&
      _listEq(other.children, children) &&
      _listEq(other.weights.map(_round).toList(), weights.map(_round).toList());

  @override
  int get hashCode => Object.hash(axis, Object.hashAll(children));

  @override
  String toString() =>
      '${axis == SplitAxis.row ? 'row' : 'col'}(${children.join(', ')})';
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Most panes one workspace may hold.
const maxPanes = 9;

/// Adds pane [newId] next to pane [targetId] on [side]. The target's
/// space is split in half. [side] must not be [DropSide.center].
LayoutNode insertPane(
  LayoutNode root,
  String targetId,
  String newId,
  DropSide side,
) {
  assert(side != DropSide.center);
  LayoutNode visit(LayoutNode node) {
    switch (node) {
      case PaneNode(:final sessionId) when sessionId == targetId:
        final pane = PaneNode(newId);
        return SplitNode(side.axis, side.before ? [pane, node] : [node, pane]);
      case PaneNode():
        return node;
      case SplitNode(:final axis, :final children, :final weights):
        final i = children.indexWhere(
          (c) => c is PaneNode && c.sessionId == targetId,
        );
        if (i >= 0 && axis == side.axis) {
          // Same direction: a new sibling sharing the target's space.
          final half = weights[i] / 2;
          final at = side.before ? i : i + 1;
          return SplitNode(
            axis,
            [...children]..insert(at, PaneNode(newId)),
            [...weights]
              ..[i] = half
              ..insert(at, half),
          );
        }
        return SplitNode(axis, [for (final c in children) visit(c)], weights);
    }
  }

  return normalize(visit(root));
}

/// Puts a whole layout [sub] next to pane [targetId] on [side] (e.g. a
/// tab with its own splits dropped onto a pane). [side] must not be
/// [DropSide.center].
LayoutNode insertLayout(
  LayoutNode root,
  String targetId,
  LayoutNode sub,
  DropSide side,
) {
  assert(side != DropSide.center);
  LayoutNode visit(LayoutNode node) => switch (node) {
    PaneNode(:final sessionId) when sessionId == targetId => SplitNode(
      side.axis,
      side.before ? [sub, node] : [node, sub],
    ),
    PaneNode() => node,
    SplitNode(:final axis, :final children, :final weights) => SplitNode(axis, [
      for (final c in children) visit(c),
    ], weights),
  };
  return normalize(visit(root));
}

/// Replaces pane [id] with pane [withId].
LayoutNode replacePane(LayoutNode root, String id, String withId) =>
    switch (root) {
      PaneNode(:final sessionId) => sessionId == id ? PaneNode(withId) : root,
      SplitNode(:final axis, :final children, :final weights) => SplitNode(
        axis,
        [for (final c in children) replacePane(c, id, withId)],
        weights,
      ),
    };

/// Removes pane [id]; null when nothing is left. The freed space goes to
/// the neighbours.
LayoutNode? removePane(LayoutNode root, String id) {
  LayoutNode? visit(LayoutNode node) {
    switch (node) {
      case PaneNode(:final sessionId):
        return sessionId == id ? null : node;
      case SplitNode(:final axis, :final children, :final weights):
        final kept = <LayoutNode>[];
        final keptWeights = <double>[];
        for (var i = 0; i < children.length; i++) {
          final c = visit(children[i]);
          if (c != null) {
            kept.add(c);
            keptWeights.add(weights[i]);
          }
        }
        if (kept.isEmpty) return null;
        if (kept.length == 1) return kept.single;
        return SplitNode(axis, kept, keptWeights);
    }
  }

  final result = visit(root);
  return result == null ? null : normalize(result);
}

/// Swaps panes [a] and [b].
LayoutNode swapPanes(LayoutNode root, String a, String b) {
  LayoutNode visit(LayoutNode node) => switch (node) {
    PaneNode(:final sessionId) when sessionId == a => PaneNode(b),
    PaneNode(:final sessionId) when sessionId == b => PaneNode(a),
    PaneNode() => node,
    SplitNode(:final axis, :final children, :final weights) => SplitNode(axis, [
      for (final c in children) visit(c),
    ], weights),
  };
  return visit(root);
}

/// Moves pane [id] next to [targetId] ([DropSide.center] swaps them).
LayoutNode movePane(
  LayoutNode root,
  String id,
  String targetId,
  DropSide side,
) {
  if (id == targetId) return root;
  if (side == DropSide.center) return swapPanes(root, id, targetId);
  final without = removePane(root, id);
  if (without == null) return root;
  return insertPane(without, targetId, id, side);
}

/// Sets the weights of the split found by [path] (child indexes from the
/// root).
LayoutNode setWeights(LayoutNode root, List<int> path, List<double> weights) {
  LayoutNode visit(LayoutNode node, int depth) {
    if (node is! SplitNode) return node;
    if (depth == path.length) {
      return SplitNode(node.axis, node.children, _normalized(weights));
    }
    final i = path[depth];
    return SplitNode(node.axis, [
      for (var k = 0; k < node.children.length; k++)
        k == i ? visit(node.children[k], depth + 1) : node.children[k],
    ], node.weights);
  }

  return visit(root, 0);
}

/// Gives every pane of every split an equal share.
LayoutNode equalize(LayoutNode root) => switch (root) {
  PaneNode() => root,
  SplitNode(:final axis, :final children) => SplitNode(axis, [
    for (final c in children) equalize(c),
  ]),
};

/// Collapses single-child splits, merges a split into a same-axis parent
/// and rescales weights to add up to 1.
LayoutNode normalize(LayoutNode node) {
  if (node is! SplitNode) return node;
  final children = <LayoutNode>[];
  final weights = <double>[];
  for (var i = 0; i < node.children.length; i++) {
    final c = normalize(node.children[i]);
    final w = node.weights[i];
    if (c is SplitNode && c.axis == node.axis) {
      for (var k = 0; k < c.children.length; k++) {
        children.add(c.children[k]);
        weights.add(w * c.weights[k]);
      }
    } else {
      children.add(c);
      weights.add(w);
    }
  }
  if (children.length == 1) return children.single;
  return SplitNode(node.axis, children, _normalized(weights));
}

List<double> _normalized(List<double> weights) {
  final sum = weights.fold<double>(0, (a, b) => a + b);
  if (sum <= 0) return List.filled(weights.length, 1 / weights.length);
  return [for (final w in weights) w / sum];
}

/// Where each pane sits inside [bounds].
Map<String, Rect> paneRects(LayoutNode root, Rect bounds) {
  final out = <String, Rect>{};
  void visit(LayoutNode node, Rect r) {
    switch (node) {
      case PaneNode(:final sessionId):
        out[sessionId] = r;
      case SplitNode(:final axis, :final children, :final weights):
        var offset = 0.0;
        for (var i = 0; i < children.length; i++) {
          final Rect child;
          if (axis == SplitAxis.row) {
            child = Rect.fromLTWH(
              r.left + r.width * offset,
              r.top,
              r.width * weights[i],
              r.height,
            );
          } else {
            child = Rect.fromLTWH(
              r.left,
              r.top + r.height * offset,
              r.width,
              r.height * weights[i],
            );
          }
          offset += weights[i];
          visit(children[i], child);
        }
    }
  }

  visit(root, bounds);
  return out;
}

/// The pane next to [id] in [direction] (the one overlapping it most),
/// or null at the edge.
String? neighbourPane(LayoutNode root, String id, PaneDirection direction) {
  final rects = paneRects(root, const Rect.fromLTWH(0, 0, 1, 1));
  final from = rects[id];
  if (from == null) return null;
  const eps = 1e-6;
  String? best;
  var bestScore = double.infinity;
  for (final e in rects.entries) {
    if (e.key == id) continue;
    final r = e.value;
    final double gap;
    final double overlap;
    switch (direction) {
      case PaneDirection.left:
        if (r.right > from.left + eps) continue;
        gap = from.left - r.right;
        overlap = _overlap(from.top, from.bottom, r.top, r.bottom);
      case PaneDirection.right:
        if (r.left < from.right - eps) continue;
        gap = r.left - from.right;
        overlap = _overlap(from.top, from.bottom, r.top, r.bottom);
      case PaneDirection.up:
        if (r.bottom > from.top + eps) continue;
        gap = from.top - r.bottom;
        overlap = _overlap(from.left, from.right, r.left, r.right);
      case PaneDirection.down:
        if (r.top < from.bottom - eps) continue;
        gap = r.top - from.bottom;
        overlap = _overlap(from.left, from.right, r.left, r.right);
    }
    if (overlap <= eps) continue;
    // Nearest first; among equally near, the one sharing the most edge.
    final score = gap * 1000 - overlap;
    if (score < bestScore) {
      bestScore = score;
      best = e.key;
    }
  }
  return best;
}

double _overlap(double a1, double a2, double b1, double b2) =>
    (a2 < b2 ? a2 : b2) - (a1 > b1 ? a1 : b1);

/// Which part of a pane of [size] the point [p] is over, for drag and
/// drop: an edge band (a quarter of the size) or the middle.
DropSide dropSideAt(Offset p, double width, double height) {
  final fx = width <= 0 ? 0.5 : p.dx / width;
  final fy = height <= 0 ? 0.5 : p.dy / height;
  final distances = {
    DropSide.left: fx,
    DropSide.right: 1 - fx,
    DropSide.top: fy,
    DropSide.bottom: 1 - fy,
  };
  final nearest = distances.entries.reduce(
    (a, b) => a.value <= b.value ? a : b,
  );
  return nearest.value < 0.25 ? nearest.key : DropSide.center;
}
