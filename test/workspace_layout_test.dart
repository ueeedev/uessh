import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/terminal/workspace_layout.dart';

void main() {
  const a = PaneNode('a');

  test('split a single pane, then split again the same way', () {
    var t = insertPane(a, 'a', 'b', DropSide.right);
    expect(t.toString(), 'row(a, b)');
    expect((t as SplitNode).weights, [0.5, 0.5]);

    // Same axis: a sibling sharing a's half, not a nested split.
    t = insertPane(t, 'a', 'c', DropSide.left);
    expect(t.toString(), 'row(c, a, b)');
    expect((t as SplitNode).weights, [0.25, 0.25, 0.5]);

    // Other axis: nests.
    t = insertPane(t, 'b', 'd', DropSide.bottom);
    expect(t.toString(), 'row(c, a, col(b, d))');
    expect(t.panes, ['c', 'a', 'b', 'd']);
  });

  test('removing collapses and hands space to neighbours', () {
    var t = insertPane(a, 'a', 'b', DropSide.right);
    t = insertPane(t, 'b', 'c', DropSide.bottom);
    expect(t.toString(), 'row(a, col(b, c))');

    final r1 = removePane(t, 'c')!;
    expect(r1.toString(), 'row(a, b)');
    final r2 = removePane(r1, 'a')!;
    expect(r2, const PaneNode('b'));
    expect(removePane(r2, 'b'), isNull);

    // Weights renormalize.
    var w = insertPane(a, 'a', 'b', DropSide.right);
    w = insertPane(w, 'b', 'c', DropSide.right); // a .5, b .25, c .25
    final r = removePane(w, 'a')! as SplitNode;
    expect(r.weights, [0.5, 0.5]);
  });

  test('a split inside a same-axis split is merged into it', () {
    // col(b, c) under a row, then a is removed: col replaces the row;
    // putting it back on the column axis must not nest col(col(...)).
    var t = insertPane(a, 'a', 'b', DropSide.right);
    t = insertPane(t, 'b', 'c', DropSide.bottom);
    t = removePane(t, 'a')!;
    expect(t.toString(), 'col(b, c)');
    t = insertPane(t, 'c', 'd', DropSide.bottom);
    expect(t.toString(), 'col(b, c, d)');
  });

  test('move and swap', () {
    var t = insertPane(a, 'a', 'b', DropSide.right);
    t = insertPane(t, 'b', 'c', DropSide.right);
    expect(t.toString(), 'row(a, b, c)');

    expect(movePane(t, 'a', 'c', DropSide.center).toString(), 'row(c, b, a)');
    expect(movePane(t, 'c', 'a', DropSide.top).toString(), 'row(col(c, a), b)');
    expect(movePane(t, 'a', 'a', DropSide.left), t);
  });

  test('weights by path; equalize', () {
    var t = insertPane(a, 'a', 'b', DropSide.right);
    t = insertPane(t, 'b', 'c', DropSide.bottom);
    t = setWeights(t, const [], [0.7, 0.3]);
    t = setWeights(t, const [1], [1, 3]);
    final s = t as SplitNode;
    expect(s.weights, [0.7, 0.3]);
    expect((s.children[1] as SplitNode).weights, [0.25, 0.75]);
    final e = equalize(t) as SplitNode;
    expect(e.weights, [0.5, 0.5]);
    expect((e.children[1] as SplitNode).weights, [0.5, 0.5]);
  });

  test('rects and moving focus by direction', () {
    // a | (b / c)
    var t = insertPane(a, 'a', 'b', DropSide.right);
    t = insertPane(t, 'b', 'c', DropSide.bottom);
    final rects = paneRects(t, const Rect.fromLTWH(0, 0, 100, 100));
    expect(rects['a'], const Rect.fromLTWH(0, 0, 50, 100));
    expect(rects['c'], const Rect.fromLTWH(50, 50, 50, 50));

    expect(neighbourPane(t, 'a', PaneDirection.right), 'b');
    expect(neighbourPane(t, 'c', PaneDirection.left), 'a');
    expect(neighbourPane(t, 'b', PaneDirection.down), 'c');
    expect(neighbourPane(t, 'c', PaneDirection.up), 'b');
    expect(neighbourPane(t, 'a', PaneDirection.left), isNull);
    expect(neighbourPane(t, 'b', PaneDirection.up), isNull);
  });

  test('drop zones: edge quarters and the middle', () {
    expect(dropSideAt(const Offset(5, 50), 100, 100), DropSide.left);
    expect(dropSideAt(const Offset(95, 50), 100, 100), DropSide.right);
    expect(dropSideAt(const Offset(50, 3), 100, 100), DropSide.top);
    expect(dropSideAt(const Offset(50, 90), 100, 100), DropSide.bottom);
    expect(dropSideAt(const Offset(50, 50), 100, 100), DropSide.center);
  });
}
