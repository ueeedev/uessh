import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';

import 'test_helpers.dart';

Host host(String n) => Host(
  id: n,
  label: n,
  address: '127.0.0.1',
  port: 1,
  username: 'u',
  authMethod: AuthMethod.password,
);

void main() {
  late TestEnv env;
  late List<String> calls;
  const channel = MethodChannel('window_manager');

  setUp(() {
    env = TestEnv();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c.method);
          return c.method == 'isMaximized' ? false : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    env.dispose();
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    List<String> tabs = const [],
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(UesshApp)));
    for (final t in tabs) {
      c.read(sessionsProvider.notifier).open(host(t));
    }
    return c;
  }

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('on the workbench, the tab strip is the title bar; page '
      'titles are not', (tester) async {
    await pumpApp(tester);
    final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    await doubleClick(tester, Offset(strip.left + 700, strip.center.dy + 6));
    expect(calls, contains('maximize'));

    calls.clear();
    await doubleClick(tester, tester.getCenter(find.text('主机').last));
    expect(calls, isNot(contains('maximize')));
    // The workbench tab itself is a tab, not empty strip.
    await doubleClick(
      tester,
      tester.getCenter(find.byKey(const ValueKey('home-tab'))),
    );
    expect(calls, isNot(contains('maximize')));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tab strip: empty space drags / maximizes; tabs do not', (
    tester,
  ) async {
    await pumpApp(tester, tabs: ['aaa', 'bbb']);
    await settleIo(tester);
    await tester.pumpAndSettle();
    final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    final blank = Offset(strip.left + 900, strip.center.dy + 6);

    await doubleClick(tester, blank);
    expect(calls, contains('maximize'));

    calls.clear();
    await mouseDrag(tester, blank, blank + const Offset(60, 20));
    expect(calls, contains('startDragging'));

    // On a tab: neither.
    calls.clear();
    await doubleClick(tester, tester.getCenter(find.text('aaa')));
    expect(calls, isNot(contains('maximize')));
    expect(calls, isNot(contains('startDragging')));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('drag a tab sideways to reorder; a gap shows where it goes', (
    tester,
  ) async {
    final c = await pumpApp(tester, tabs: ['one', 'two', 'three']);
    await tester.pump(); // opening a session shows its tab
    await settleIo(tester);
    await tester.pumpAndSettle();
    List<String> order() {
      final s = c.read(sessionsProvider);
      return [for (final t in s.tabs) s.session(t.focusedId)!.host.label];
    }

    // "one" to after "three".
    final from = tester.getCenter(find.text('one'));
    final to = tester.getCenter(find.text('three')) + const Offset(80, 0);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 12)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 200));
    // The others slid left into the dragged tab's place; a gap after them.
    expect(
      tester.getTopLeft(find.text('two')).dx,
      lessThan(from.dx),
      reason: 'closed up',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is AnimatedPadding && (w.padding as EdgeInsets).left > 100,
      ),
      findsOneWidget,
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(order(), ['two', 'three', 'one']);

    // And back to the front.
    await mouseDrag(
      tester,
      tester.getCenter(find.text('one')),
      tester.getCenter(find.text('two')) - const Offset(90, 0),
    );
    expect(order(), ['one', 'two', 'three']);
    expect(calls, isNot(contains('startDragging')));
    debugDefaultTargetPlatformOverride = null;
  });
}
