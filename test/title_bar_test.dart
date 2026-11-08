import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/widgets/page_scaffold.dart';
import 'package:uessh/widgets/window_drag_area.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<Rect> pumpAndGetLogo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    return tester.getRect(find.byKey(const ValueKey('app-logo')));
  }

  testWidgets('macOS: content reaches the top; headers act as title bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final logo = await pumpAndGetLogo(tester);

    // Logo sits below the traffic lights (28px band at the top).
    expect(logo.top, greaterThanOrEqualTo(28 + 16));

    // Sidebar top and the page header can drag the window.
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('app-logo')),
        matching: find.byType(WindowDragArea),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PageScaffold).first,
        matching: find.byType(WindowDragArea),
      ),
      findsOneWidget,
    );

    // Empty header space hits the drag surface...
    final header = tester.getRect(
      find.descendant(
        of: find.byType(PageScaffold).first,
        matching: find.byType(WindowDragArea),
      ),
    );
    final hit = tester.hitTestOnBinding(
      Offset(header.center.dx, header.top + 6),
    );
    final surface = tester.renderObject(
      find.byKey(const ValueKey('window-drag-surface')).at(1),
    );
    expect(hit.path.any((e) => e.target == surface), isTrue);

    // ...while buttons respond to a single click right away (no waiting
    // to rule out a double-click).
    await tester.tap(find.text('新建主机'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('新建主机'), findsWidgets);
    expect(find.text('地址'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: own caption buttons; headers act as title bar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final logo = await pumpAndGetLogo(tester);
    // No traffic lights to clear on Windows.
    expect(logo.top, lessThan(28));

    // Minimize / maximize / close sit in the top right corner.
    final caption = tester.getRect(
      find.byKey(const ValueKey('window-caption-buttons')),
    );
    expect(caption.topRight, const Offset(1200, 0));
    expect(caption.size, Size(captionButtonSize.width * 3, 32));
    expect(find.byKey(const ValueKey('caption-minimize')), findsOneWidget);
    expect(find.byKey(const ValueKey('caption-maximize')), findsOneWidget);
    expect(find.byKey(const ValueKey('caption-close')), findsOneWidget);

    // Page headers drag the window, and their buttons start below the
    // caption buttons.
    expect(find.byKey(const ValueKey('window-drag-surface')), findsWidgets);
    final newHost = tester.getRect(find.text('新建主机'));
    expect(newHost.top, greaterThanOrEqualTo(caption.bottom));
    debugDefaultTargetPlatformOverride = null;
  });
}
