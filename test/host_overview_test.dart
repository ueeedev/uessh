import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host_overview.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/terminal/terminal_page.dart';
import 'package:uessh/l10n/l10n.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() {
    env = TestEnv();
    File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[{"id":"g","name":"生产"}],"hosts":[
 {"id":"a","label":"web-01","address":"10.0.0.1","port":22,"username":"u","authMethod":"password","groupId":"g"},
 {"id":"b","label":"db","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"},
 {"id":"c","label":"gw","address":"10.0.0.3","port":22,"username":"u","authMethod":"password"}
]}''');
    env.reachability.up['10.0.0.1'] = const Duration(milliseconds: 9);
  });
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

  String textIn(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data)
      .join('|');

  testWidgets('counts hosts, groups, online and unreachable', (tester) async {
    await pumpApp(tester);
    expect(textIn(tester, 'overview-total'), contains('3'));
    expect(textIn(tester, 'overview-total'), contains('1 个分组'));
    expect(textIn(tester, 'overview-online'), startsWith('在线|1|'));
    expect(textIn(tester, 'overview-lost'), startsWith('失联|2|'));
    expect(textIn(tester, 'overview-last'), contains('还没有连接过主机'));
  });

  testWidgets('layout: total / online / lost in one card, last on its own', (
    tester,
  ) async {
    await pumpApp(tester);
    final stats = find.byKey(const ValueKey('overview-stats'));
    final last = find.byKey(const ValueKey('overview-last'));
    for (final k in ['overview-total', 'overview-online', 'overview-lost']) {
      expect(
        find.descendant(of: stats, matching: find.byKey(ValueKey(k))),
        findsOneWidget,
        reason: '$k inside the shared card',
      );
    }
    expect(
      find.descendant(of: stats, matching: find.byType(VerticalDivider)),
      findsNWidgets(2),
    );

    // Side by side, numbers on one line.
    final r = [
      for (final k in ['overview-total', 'overview-online', 'overview-lost'])
        tester.getRect(find.byKey(ValueKey(k))),
    ];
    expect(r[1].left, greaterThan(r[0].right));
    expect(r[2].left, greaterThan(r[1].right));
    Rect numberOf(String k, String text) => tester.getRect(
      find.descendant(of: find.byKey(ValueKey(k)), matching: find.text(text)),
    );
    final n = [
      numberOf('overview-total', '3'),
      numberOf('overview-online', '1'),
      numberOf('overview-lost', '2'),
    ];
    expect(n[1].top, n[0].top);
    expect(n[2].top, n[0].top);

    final statsRect = tester.getRect(stats), lastRect = tester.getRect(last);
    expect(lastRect.left, greaterThan(statsRect.right));
    expect(lastRect.height, statsRect.height);
    expect(statsRect.width, closeTo(lastRect.width * 1.5, 1));

    // The two cards use different background shapes.
    OverviewShape shapeOf(Finder card) =>
        (tester
                    .widget<CustomPaint>(
                      find
                          .descendant(
                            of: card,
                            matching: find.byWidgetPredicate(
                              (w) =>
                                  w is CustomPaint &&
                                  w.painter is OverviewShapePainter,
                            ),
                          )
                          .first,
                    )
                    .painter!
                as OverviewShapePainter)
            .shape;
    expect(shapeOf(stats), isNot(shapeOf(last)));
  });

  testWidgets('last connected host: name, time and a connect button', (
    tester,
  ) async {
    env.settings = AppSettings(
      language: AppLanguage.zh,
      lastConnectedHostId: 'b',
      lastConnectedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    await pumpApp(tester);
    expect(textIn(tester, 'overview-last'), contains('db'));
    expect(textIn(tester, 'overview-last'), contains('5 分钟前'));

    await tester.tap(find.byKey(const ValueKey('overview-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BrowserTab), findsOneWidget, reason: 'session opened');
    expect(
      tester.widget<BrowserTab>(find.byType(BrowserTab)).session.host.id,
      'b',
    );
    // Let the (refused) connection finish so no timers are left behind.
    await pumpUntil(tester, () => find.text('重新连接').evaluate().isNotEmpty);
  });

  testWidgets('checks off: counts show a dash', (tester) async {
    env.settings = const AppSettings(
      language: AppLanguage.zh,
      checkIntervalSeconds: 0,
    );
    await pumpApp(tester);
    expect(textIn(tester, 'overview-online'), '在线|—|检测已关闭');
  });

  testWidgets('hidden while searching and when turned off', (tester) async {
    await pumpApp(tester);
    expect(find.byType(HostOverview), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), 'db');
    await tester.pumpAndSettle();
    expect(find.byType(HostOverview), findsNothing);
    await tester.enterText(find.byType(SearchBar), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('show-overview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主机').first);
    await tester.pumpAndSettle();
    expect(find.byType(HostOverview), findsNothing);
  });

  test('time ago', () {
    final l = lookupAppLocalizations(const Locale('zh'));
    final now = DateTime(2026, 1, 1, 12);
    expect(
      formatTimeAgo(l, now.subtract(const Duration(seconds: 20)), now: now),
      '刚刚',
    );
    expect(
      formatTimeAgo(l, now.subtract(const Duration(minutes: 7)), now: now),
      '7 分钟前',
    );
    expect(
      formatTimeAgo(l, now.subtract(const Duration(hours: 3)), now: now),
      '3 小时前',
    );
    expect(
      formatTimeAgo(l, now.subtract(const Duration(days: 2)), now: now),
      '2 天前',
    );
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      formatTimeAgo(en, now.subtract(const Duration(minutes: 1)), now: now),
      '1 minute ago',
    );
  });
}
