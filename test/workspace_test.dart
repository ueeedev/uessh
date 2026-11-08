import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_page.dart';
import 'package:uessh/features/terminal/workspace_layout.dart';

import 'test_helpers.dart';

Host host(String name) => Host(
  id: name,
  label: name,
  address: '127.0.0.1',
  port: 1, // refused at once: tabs settle as "failed"
  username: 'root',
  authMethod: AuthMethod.password,
);

void main() {
  group('workspace state', () {
    late TestEnv env;
    late ProviderContainer c;
    setUp(() {
      env = TestEnv();
      c = ProviderContainer(overrides: env.overrides);
    });
    tearDown(() {
      c.dispose();
      env.dispose();
    });

    SessionsNotifier n() => c.read(sessionsProvider.notifier);
    SessionsState s() => c.read(sessionsProvider);
    String name(String id) => s().session(id)!.host.label;
    List<String> names(WorkspaceTab t) => t.paneIds.map(name).toList();

    test('split, focus by direction, close collapses', () {
      final a = n().open(host('a'));
      final b = n().open(host('b'), splitFrom: a.id);
      final cc = n().open(host('c'), splitFrom: b.id, side: DropSide.bottom);
      expect(s().tabs, hasLength(1));
      final tab = s().tabs.single;
      expect(tab.layout.toString(), 'row(${a.id}, col(${b.id}, ${cc.id}))');
      expect(s().active, cc, reason: 'new pane is focused');

      n().focusNeighbour(PaneDirection.up);
      expect(s().active, b);
      n().focusNeighbour(PaneDirection.left);
      expect(s().active, a);
      n().focusNeighbour(PaneDirection.left);
      expect(s().active, a, reason: 'edge: stays');

      n().close(a.id);
      expect(names(s().tabs.single), ['b', 'c']);
      expect(s().tabs.single.layout, isA<SplitNode>());
      expect(s().active, isNotNull);
      n().close(b.id);
      n().close(cc.id);
      expect(s().tabs, isEmpty);
      expect(s().sessions, isEmpty);
    });

    test('move panes within and across tabs; detach; reorder', () {
      final a = n().open(host('a'));
      final b = n().open(host('b'), splitFrom: a.id);
      final x = n().open(host('x')); // second tab
      expect(s().tabs, hasLength(2));

      // Swap within a tab.
      n().movePaneTo(a.id, b.id, DropSide.center);
      expect(names(s().tabs.first), ['b', 'a']);

      // x (a whole tab) moves under a: its tab disappears.
      expect(n().movePaneTo(x.id, a.id, DropSide.bottom), isTrue);
      expect(s().tabs, hasLength(1));
      expect(names(s().tabs.single), ['b', 'a', 'x']);
      expect(s().active, x);

      // Back out into its own tab, first in the strip.
      n().detachToTab(x.id, index: 0);
      expect(s().tabs, hasLength(2));
      expect(names(s().tabs.first), ['x']);
      expect(s().activeTab, s().tabs.first);

      // Reorder tabs.
      n().moveTab(s().tabs.first.id, 2);
      expect(names(s().tabs.last), ['x']);
    });

    test('a split tab dropped on a pane joins that workspace', () {
      final a = n().open(host('a'));
      final x = n().open(host('x'));
      final y = n().open(host('y'), splitFrom: x.id);
      final xyTab = s().tabOf(x.id)!;
      expect(n().mergeTabInto(xyTab.id, a.id, DropSide.right), isTrue);
      expect(s().tabs, hasLength(1));
      expect(names(s().tabs.single), ['a', 'x', 'y']);
      expect(s().active, y, reason: 'keeps the dropped tab\'s focus');
    });

    test('at most 9 panes per workspace', () {
      final first = n().open(host('p0'));
      for (var i = 1; i < maxPanes; i++) {
        n().open(host('p$i'), splitFrom: first.id);
      }
      expect(s().tabs.single.paneIds, hasLength(maxPanes));
      // A 10th opens as a new tab instead.
      n().open(host('extra'), splitFrom: first.id);
      expect(s().tabs, hasLength(2));
      final extra = s().tabs.last.focusedId;
      expect(n().movePaneTo(extra, first.id, DropSide.left), isFalse);
    });

    test('workspaces are numbered when they become split; rename', () {
      final a = n().open(host('a'));
      final x = n().open(host('x'));
      expect(s().tabOf(a.id)!.number, isNull, reason: 'one pane: no name');
      n().open(host('b'), splitFrom: a.id);
      n().open(host('y'), splitFrom: x.id);
      expect(s().tabOf(a.id)!.number, 1);
      expect(s().tabOf(x.id)!.number, 2);

      n().rename(s().tabOf(a.id)!.id, '  生产集群 ');
      expect(s().tabOf(a.id)!.name, '生产集群');
      n().rename(s().tabOf(a.id)!.id, '');
      expect(s().tabOf(a.id)!.name, isNull, reason: 'empty: default again');

      // Back to one pane: the number is free for the next workspace.
      n().close(s().tabOf(a.id)!.paneIds.last);
      expect(s().tabOf(a.id)!.number, isNull);
      final z = n().open(host('z'));
      n().open(host('w'), splitFrom: z.id);
      expect(s().tabOf(z.id)!.number, 1);
    });

    test('zoom shows one pane; broadcast mirrors typing', () {
      final a = n().open(host('a'));
      final b = n().open(host('b'), splitFrom: a.id);
      n().toggleZoom(a.id);
      expect(s().activeTab!.zoomedId, a.id);
      n().activate(b.id); // focusing another pane un-zooms
      expect(s().activeTab!.zoomedId, isNull);

      final got = <String>[];
      b.debugOnSend = got.add;
      expect(a.onUserInput, isNull);
      n().toggleBroadcast(s().activeTab!.id);
      a.onUserInput!('uptime\r');
      expect(got, ['uptime\r']);
      n().toggleBroadcast(s().activeTab!.id);
      expect(a.onUserInput, isNull);
    });
  });

  group('workspace UI', () {
    late TestEnv env;
    setUp(() {
      env = TestEnv();
      File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[],"hosts":[
 {"id":"pick","label":"picked-host","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"}
]}''');
    });
    tearDown(() => env.dispose());

    Future<ProviderContainer> pumpWith(
      WidgetTester tester,
      List<String> tabs, {
      bool split = false,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(UesshApp)),
      );
      final n = c.read(sessionsProvider.notifier);
      String? first;
      for (final t in tabs) {
        final s = n.open(host(t), splitFrom: split ? first : null);
        first ??= s.id;
      }
      await tester.pump(); // opening a session shows its tab
      await settleIo(tester);
      await tester.pumpAndSettle();
      return c;
    }

    final cards = find.byKey(const ValueKey('terminal-card'));

    testWidgets('a split tab: two cards, headers, "+1" badge, click focus', (
      tester,
    ) async {
      final c = await pumpWith(tester, ['left', 'right'], split: true);
      expect(cards, findsNWidgets(2));
      final l = tester.getRect(cards.at(0)), r = tester.getRect(cards.at(1));
      expect(r.left, greaterThan(l.right));
      expect((r.left - l.right).round(), 8, reason: 'gap between panes');
      expect(find.byKey(const ValueKey('tab-pane-count')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tab-pane-count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      // A split tab is a workspace: its name, not a host's.
      expect(find.text('工作区 1'), findsOneWidget);
      expect(find.text('left'), findsWidgets); // pane header

      // Click the left pane: it becomes the focused one.
      await tester.tapAt(l.center);
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).active!.host.label, 'left');
    });

    testWidgets('click the current workspace tab to rename it', (tester) async {
      final c = await pumpWith(tester, ['left', 'right'], split: true);
      final tabId = c.read(sessionsProvider).tabs.single.id;
      await tester.tap(find.text('工作区 1'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('rename-workspace'));
      expect(field, findsOneWidget);
      // While typing, the tab can't be dragged.
      expect(
        tester
            .widget<Draggable<Object>>(
              find.ancestor(
                of: field,
                matching: find.byType(Draggable<Object>),
              ),
            )
            .maxSimultaneousDrags,
        0,
      );

      await tester.enterText(field, '数据库');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('数据库'), findsOneWidget);
      expect(c.read(sessionsProvider).tabById(tabId)!.name, '数据库');

      // Esc cancels.
      await tester.tap(find.text('数据库'));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'nope');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(find.text('数据库'), findsOneWidget);
    });

    testWidgets('a single-pane tab is not renamed by clicking', (tester) async {
      await pumpWith(tester, ['solo']);
      await tester.tap(find.byType(BrowserTab));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rename-workspace')), findsNothing);
    });

    testWidgets('drag the divider; double-click evens it out', (tester) async {
      final c = await pumpWith(tester, ['left', 'right'], split: true);
      final divider = find.byKey(const ValueKey('divider--0'));
      expect(divider, findsOneWidget);
      final before = tester.getRect(cards.at(0)).width;
      await tester.drag(divider, const Offset(120, 0));
      await tester.pumpAndSettle();
      final after = tester.getRect(cards.at(0)).width;
      expect(after - before, closeTo(120, 2));
      final w =
          (c.read(sessionsProvider).activeTab!.layout as SplitNode).weights;
      expect(w.first, greaterThan(0.5));

      await tester.tap(divider);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(divider);
      await tester.pumpAndSettle();
      expect(
        (c.read(sessionsProvider).activeTab!.layout as SplitNode).weights,
        [0.5, 0.5],
      );
    });

    testWidgets('macOS keys: ⌘D splits via the host picker, ⌘⌥← focus, '
        '⌘⇧Enter zoom', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = await pumpWith(tester, ['one']);

      Future<void> keys(
        List<LogicalKeyboardKey> mods,
        LogicalKeyboardKey k,
      ) async {
        for (final m in mods) {
          await tester.sendKeyDownEvent(m);
        }
        await tester.sendKeyEvent(k);
        for (final m in mods.reversed) {
          await tester.sendKeyUpEvent(m);
        }
        await tester.pumpAndSettle();
      }

      await keys([LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyD);
      expect(find.byKey(const ValueKey('host-picker')), findsOneWidget);
      await tester.tap(find.text('picked-host'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      final tab = c.read(sessionsProvider).activeTab!;
      expect(tab.paneIds, hasLength(2));
      expect(c.read(sessionsProvider).active!.host.label, 'picked-host');

      await keys([
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.altLeft,
      ], LogicalKeyboardKey.arrowLeft);
      expect(c.read(sessionsProvider).active!.host.label, 'one');

      await keys([
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.enter);
      expect(cards, findsOneWidget, reason: 'zoomed: one pane shown');
      await keys([
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.enter);
      expect(cards, findsNWidgets(2));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Windows keys: Ctrl+Shift+E splits down, Alt+↑ focus', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = await pumpWith(tester, ['top']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('picked-host'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      final layout = c.read(sessionsProvider).activeTab!.layout as SplitNode;
      expect(layout.axis, SplitAxis.column);
      final t = tester.getRect(cards.at(0)), b = tester.getRect(cards.at(1));
      expect(b.top, greaterThan(t.bottom));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).active!.host.label, 'top');
      debugDefaultTargetPlatformOverride = null;
    });

    Future<void> dragFromTo(WidgetTester tester, Offset from, Offset to) async {
      final g = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 12)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    testWidgets('drag a tab onto the right half of a pane: they split', (
      tester,
    ) async {
      final c = await pumpWith(tester, ['base', 'moved']);
      expect(c.read(sessionsProvider).tabs, hasLength(2));
      // Show the "base" tab, then drag the "moved" tab onto its pane.
      await tester.tap(find.text('base'));
      await tester.pumpAndSettle();
      final card = tester.getRect(cards.first);
      final from = tester.getCenter(find.text('moved'));
      final to = Offset(card.right - 30, card.center.dy);

      final g = await tester.startGesture(from);
      await tester.pump();
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 12)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('drop-preview')), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();

      final state = c.read(sessionsProvider);
      expect(state.tabs, hasLength(1));
      expect(
        state.tabs.single.paneIds.map((id) => state.session(id)!.host.label),
        ['base', 'moved'],
      );
      expect(cards, findsNWidgets(2));
    });

    testWidgets('drag a pane header to the tab strip: its own tab again', (
      tester,
    ) async {
      final c = await pumpWith(tester, ['stay', 'go'], split: true);
      final s = c.read(sessionsProvider);
      final goId = s.tabs.single.paneIds.last;
      final header = find.byKey(ValueKey('pane-header-$goId'));
      final from = tester.getTopLeft(header) + const Offset(40, 14);
      final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
      await dragFromTo(tester, from, Offset(strip.left + 500, strip.center.dy));

      final after = c.read(sessionsProvider);
      expect(after.tabs, hasLength(2));
      expect(after.tabs.last.paneIds, [goId]);
      expect(after.activeTab, after.tabs.last);
      expect(cards, findsOneWidget);
    });

    testWidgets('closing a split tab asks once for all its connections', (
      tester,
    ) async {
      final c = await pumpWith(tester, ['a', 'b'], split: true);
      // Failed connections: nothing live, so it closes straight away.
      final tab = c.read(sessionsProvider).tabs.single;
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('tab-${tab.id}')),
          matching: find.byTooltip('关闭'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).tabs, isEmpty);
      expect(find.byType(BrowserTab), findsNothing);
    });
  });
}
