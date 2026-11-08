import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/terminal/info_panel.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_page.dart';
import 'package:uessh/theme/terminal_theme.dart';
import 'package:xterm2/xterm.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  /// Opens the terminal page with one session to a port nobody listens
  /// on, so it fails fast without real network access.
  Future<void> pumpWithSession(WidgetTester tester) async {
    final port = (await tester.runAsync(() async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = s.port;
      await s.close();
      return p;
    }))!;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UesshApp)),
    );
    container
        .read(sessionsProvider.notifier)
        .open(
          Host(
            id: 'h',
            label: 'test-box',
            address: '127.0.0.1',
            port: port,
            username: 'root',
            authMethod: AuthMethod.password,
          ),
        );
    await tester.tap(find.text('终端'));
    await pumpUntil(tester, () => find.text('重新连接').evaluate().isNotEmpty);
  }

  testWidgets('the terminal sits in a card with rounded corners', (
    tester,
  ) async {
    await pumpWithSession(tester);
    final card = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('terminal-card')),
    );
    expect(card.borderRadius, BorderRadius.circular(terminalCardRadius));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('terminal-card')),
        matching: find.byType(TerminalView),
      ),
      findsOneWidget,
    );
    // Inset from the page edges so the corners are visible.
    final rect = tester.getRect(find.byKey(const ValueKey('terminal-card')));
    final page = tester.getRect(find.byType(TerminalPage));
    expect(rect.right, lessThan(page.right));
    expect(rect.bottom, lessThan(page.bottom));
  });

  testWidgets('info panel slides in beside the terminal and is remembered', (
    tester,
  ) async {
    await pumpWithSession(tester);
    expect(find.byType(TerminalInfoPanel), findsNothing);
    final fullWidth = tester
        .getRect(find.byKey(const ValueKey('terminal-card')))
        .width;

    await tester.tap(find.byTooltip('显示信息栏'));
    await tester.pump(); // animation starts on this frame
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getRect(find.byKey(const ValueKey('terminal-card')));
    expect(mid.width, lessThan(fullWidth));
    expect(mid.width, greaterThan(fullWidth - infoPanelWidth - 12));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(TerminalInfoPanel));
    final card = tester.getRect(find.byKey(const ValueKey('terminal-card')));
    expect(panel.width, infoPanelWidth);
    expect(panel.left, greaterThan(card.right), reason: 'right of terminal');
    expect(card.width, closeTo(fullWidth - infoPanelWidth - 12, 0.5));

    // Connection details for this session.
    expect(find.text('test-box'), findsWidgets);
    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('连接后显示服务器的系统信息'), findsOneWidget);

    await settleIo(tester);
    final saved = (await tester.runAsync(
      () => SettingsStore(dataDir: env.dataDir).load(),
    ))!;
    expect(saved.showTerminalInfo, isTrue);

    await tester.tap(find.byTooltip('关闭信息栏'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalInfoPanel), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('terminal-card'))).width,
      fullWidth,
    );
  });

  group('closing tabs', () {
    /// A session stuck in "connecting": the server accepts the TCP
    /// connection but never speaks SSH.
    Future<void> pumpWithLiveSession(WidgetTester tester) async {
      final server = (await tester.runAsync(
        () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      final held = <Socket>[];
      server.listen(held.add);
      addTearDown(() async {
        await tester.runAsync(() async {
          for (final s in held) {
            s.destroy();
          }
          await server.close();
        });
      });
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);
      ProviderScope.containerOf(tester.element(find.byType(UesshApp)))
          .read(sessionsProvider.notifier)
          .open(
            Host(
              id: 'live',
              label: 'live-box',
              address: '127.0.0.1',
              port: server.port,
              username: 'root',
              authMethod: AuthMethod.password,
            ),
          );
      await tester.tap(find.text('终端'));
      // The connecting animation never settles, so pump by time.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('正在连接'), findsWidgets);
    }

    Future<void> pressClose(WidgetTester tester, LogicalKeyboardKey mod) async {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(mod);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    final confirm = find.text('关闭标签页？');
    final tab = find.text('live-box');

    testWidgets('macOS: ⌘W asks first; cancel keeps the tab', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpWithLiveSession(tester);

      await pressClose(tester, LogicalKeyboardKey.metaLeft);
      expect(confirm, findsOneWidget);
      expect(find.textContaining('live-box 的 SSH 连接会断开'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(confirm, findsNothing);
      expect(tab, findsWidgets, reason: 'still open');

      await pressClose(tester, LogicalKeyboardKey.metaLeft);
      await tester.tap(find.widgetWithText(FilledButton, '关闭'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tab, findsNothing);
      expect(find.text('没有打开的会话'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Windows: Ctrl+W asks first, Enter confirms', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpWithLiveSession(tester);

      await pressClose(tester, LogicalKeyboardKey.controlLeft);
      expect(confirm, findsOneWidget);
      // A second Ctrl+W while asking doesn't stack another dialog.
      await pressClose(tester, LogicalKeyboardKey.controlLeft);
      expect(confirm, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tab, findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the tab close button asks too', (tester) async {
      await pumpWithLiveSession(tester);
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(confirm, findsOneWidget);
    });

    testWidgets('a failed connection closes without asking', (tester) async {
      await pumpWithSession(tester); // connection refused -> failed
      await tester.tap(find.byTooltip('关闭').first);
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.text('没有打开的会话'), findsOneWidget);
    });
  });

  testWidgets('tabs look like browser tabs: selected one joins the page', (
    tester,
  ) async {
    await pumpWithSession(tester);
    final tab = find.byType(BrowserTab);
    expect(tab, findsOneWidget);

    final painter =
        tester
                .widget<CustomPaint>(
                  find
                      .descendant(of: tab, matching: find.byType(CustomPaint))
                      .first,
                )
                .painter!
            as BrowserTabPainter;
    final scheme = Theme.of(tester.element(tab)).colorScheme;
    // Selected tab = the terminal window's background, unlike the strip.
    expect(painter.fill, terminalThemeFor(scheme).background);
    final strip = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('tab-strip')),
    );
    expect(strip.color, isNot(painter.fill));

    // The tab sits right on top of the terminal card: one piece.
    final tabRect = tester.getRect(tab);
    final card = tester.getRect(find.byKey(const ValueKey('terminal-card')));
    expect(tabRect.bottom, card.top);
    // ...and its curved feet land past the card's rounded corner.
    expect(
      tabRect.left - BrowserTabPainter.foot,
      greaterThanOrEqualTo(card.left + terminalCardRadius),
    );

    // The outline curves out past both sides at the bottom.
    final bounds = BrowserTabPainter.tabPath(const Size(200, 38)).getBounds();
    expect(bounds.left, -BrowserTabPainter.foot);
    expect(bounds.right, 200 + BrowserTabPainter.foot);
  });

  testWidgets('drag the handle to resize the info panel; it is remembered', (
    tester,
  ) async {
    await pumpWithSession(tester);
    await tester.tap(find.byTooltip('显示信息栏'));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('terminal-card'));
    final handle = find.byKey(const ValueKey('info-panel-handle'));
    final cardBefore = tester.getRect(card).width;
    expect(tester.getRect(find.byType(TerminalInfoPanel)).width, 300);

    // Drag left: the panel grows by the same amount, the terminal shrinks.
    await tester.drag(handle, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(TerminalInfoPanel)).width,
      closeTo(400, 1),
    );
    expect(tester.getRect(card).width, closeTo(cardBefore - 100, 1));

    await settleIo(tester);
    final saved = (await tester.runAsync(
      () => SettingsStore(dataDir: env.dataDir).load(),
    ))!;
    expect(saved.infoPanelWidth, closeTo(400, 1));

    // Clamped at both ends.
    await tester.drag(handle, const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(TerminalInfoPanel)).width,
      AppSettings.minInfoPanelWidth,
    );
    await tester.drag(handle, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byType(TerminalPage)).width;
    expect(
      tester.getRect(find.byType(TerminalInfoPanel)).width,
      lessThanOrEqualTo(page * 0.6),
    );

    // Double-click resets to the default.
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TerminalInfoPanel)).width, 300);
  });

  testWidgets('"+" is a square button with the icon centred', (tester) async {
    await pumpWithSession(tester);
    final plus = find.byKey(const ValueKey('new-tab'));
    final box = tester.getRect(plus);
    expect(box.size, const Size.square(newTabButtonSize));
    final icon = tester.getCenter(
      find.descendant(of: plus, matching: find.byIcon(Icons.add)),
    );
    expect((icon - box.center).distance, lessThan(0.5));
    // Vertically centred on the tabs.
    final tab = tester.getRect(find.byType(BrowserTab).first);
    expect((box.center.dy - tab.center.dy).abs(), lessThan(0.5));
  });

  group('new session picker', () {
    void writeHosts() {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[{"id":"g","name":"生产"}],"hosts":[
 {"id":"a","label":"alpha","address":"127.0.0.1","port":1,"username":"u","authMethod":"password","groupId":"g"},
 {"id":"b","label":"bravo","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"},
 {"id":"c","label":"charlie","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"}
]}''');
    }

    final picker = find.byKey(const ValueKey('host-picker'));

    testWidgets('"+" after the last tab opens the host list under it', (
      tester,
    ) async {
      writeHosts();
      await pumpWithSession(tester);
      final plus = find.byKey(const ValueKey('new-tab'));
      final lastTab = tester.getRect(find.byType(BrowserTab).last);
      final plusRect = tester.getRect(plus);
      expect(plusRect.left, greaterThanOrEqualTo(lastTab.right));
      expect(
        plusRect.left - lastTab.right,
        lessThan(40),
        reason: 'right after',
      );

      await tester.tap(plus);
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);
      final p = tester.getRect(picker);
      expect(p.top, greaterThan(plusRect.bottom), reason: 'drops below');
      expect((p.left - plusRect.left).abs(), lessThan(1));
      expect(find.text('生产'), findsOneWidget, reason: 'grouped');
      expect(find.text('alpha'), findsOneWidget);

      // Search, then ↓ + Enter opens the second match.
      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'a',
      );
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('bravo'), findsOneWidget);
      expect(find.text('charlie'), findsOneWidget);
      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'r',
      );
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(picker, findsNothing);
      expect(find.byType(BrowserTab), findsNWidgets(2));
      final active = tester
          .widgetList<BrowserTab>(find.byType(BrowserTab))
          .firstWhere((t) => t.selected);
      expect(active.session.host.label, 'charlie');
    });

    testWidgets('clicking a host opens it; Esc closes without opening', (
      tester,
    ) async {
      writeHosts();
      await pumpWithSession(tester);
      await tester.tap(find.byKey(const ValueKey('new-tab')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(find.byType(BrowserTab), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bravo'));
      await tester.pumpAndSettle();
      expect(find.byType(BrowserTab), findsNWidgets(2));
    });

    testWidgets('empty terminal page has a "new session" button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);
      await tester.tap(find.text('终端'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('empty-new-session')));
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);

      // No hosts yet: offer to go and add one.
      expect(find.text('还没有主机'), findsWidgets);
      await tester.tap(find.text('去添加主机'));
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(find.text('新建主机'), findsOneWidget, reason: 'on hosts page');
    });
  });
}
