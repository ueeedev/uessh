import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/shell/home_shell.dart';
import 'package:uessh/widgets/window_drag_area.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
  }

  testWidgets('macOS: the tab strip is the top of the window; tabs start '
      'right of the window buttons', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpApp(tester);
    final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    expect(strip.top, 0);
    expect(strip.width, 1200);
    final home = tester.getRect(find.byKey(const ValueKey('home-tab')));
    expect(home.left, greaterThanOrEqualTo(80), reason: 'traffic lights');
    // The workbench (sidebar with the logo) sits below, in its card.
    final card = tester.getRect(find.byKey(const ValueKey('home-card')));
    expect(card.top, strip.bottom);
    expect(
      tester.getRect(find.byKey(const ValueKey('app-logo'))).top,
      greaterThan(card.top),
    );
    // The line after the workbench tab continues the sidebar's edge.
    final line = tester.getRect(find.byKey(const ValueKey('home-tab-divider')));
    expect(
      line.left,
      tester.getRect(find.byKey(const ValueKey('home-card'))).left +
          sideNavWidth,
    );
    // Buttons on pages answer a single click at once.
    await tester.tap(find.text('新建主机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('地址'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: own caption buttons over the strip\'s right end', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pumpApp(tester);
    final caption = tester.getRect(
      find.byKey(const ValueKey('window-caption-buttons')),
    );
    expect(caption.topRight, const Offset(1200, 0));
    expect(caption.size, Size(captionButtonSize.width * 3, 32));
    final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    expect(strip.top, 0);
    // No window buttons on the left: tabs start near the edge.
    expect(
      tester.getRect(find.byKey(const ValueKey('home-tab'))).left,
      lessThan(60),
    );
    // The line after the workbench tab continues the sidebar's edge.
    final line = tester.getRect(find.byKey(const ValueKey('home-tab-divider')));
    expect(
      line.left,
      tester.getRect(find.byKey(const ValueKey('home-card'))).left +
          sideNavWidth,
    );
    // Page content starts below the strip, clear of the caption buttons.
    expect(
      tester.getRect(find.text('新建主机')).top,
      greaterThanOrEqualTo(caption.bottom),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
