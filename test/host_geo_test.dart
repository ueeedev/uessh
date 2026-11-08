import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host_geo.dart';
import 'package:uessh/features/hosts/host_avatar.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() {
    env = TestEnv();
    File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[],"hosts":[
 {"id":"a","label":"tokyo","address":"203.0.113.5","port":22,"username":"u","authMethod":"password","icon":{"kind":"flag"}},
 {"id":"b","label":"lan","address":"192.168.1.20","port":22,"username":"u","authMethod":"password","icon":{"kind":"flag"}},
 {"id":"c","label":"named","address":"web.example.com","port":22,"username":"u","authMethod":"password","icon":{"kind":"flag"}},
 {"id":"d","label":"plain","address":"192.0.2.9","port":22,"username":"u","authMethod":"password"}
]}''');
    env.geo.places['203.0.113.5'] = 'JP';
    env.geo.places['198.51.100.7'] = 'DE';
    env.geo.dns['web.example.com'] = '198.51.100.7';
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
    await settleIo(tester);
  }

  Future<void> openMoreSettings(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('more-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('icon-kind')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('icon-kind')));
    await tester.pumpAndSettle();
  }

  Finder flagOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Card)),
    matching: find.byKey(const ValueKey('host-flag')),
  );

  testWidgets('public hosts show their flag; private ones keep the letter', (
    tester,
  ) async {
    await pumpApp(tester);
    await pumpUntil(
      tester,
      () => tester.any(flagOf('tokyo')) && tester.any(flagOf('named')),
    );
    expect(flagOf('tokyo'), findsOneWidget);
    expect(flagOf('named'), findsOneWidget); // resolved through DNS first
    expect(flagOf('lan'), findsNothing);
    expect(find.text('L'), findsOneWidget); // "lan" keeps its letter

    // Private addresses never leave the machine.
    expect(env.geo.lookups, unorderedEquals(['203.0.113.5', '198.51.100.7']));
    // Each flag is downloaded once and kept on disk.
    expect(File('${env.dataDir.path}/geo/flags/jp.svg').existsSync(), isTrue);
    expect(find.byTooltip('City, Region, Country JP'), findsOneWidget);
  });

  testWidgets('answers are cached: the next launch asks nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    await pumpUntil(
      tester,
      () => tester.any(flagOf('tokyo')) && tester.any(flagOf('named')),
    );
    expect(env.geo.lookups, hasLength(2));
    await tester.pumpWidget(const SizedBox());

    env.geo.lookups.clear();
    env.geo.downloads.clear();
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await pumpUntil(tester, () => tester.any(flagOf('named')));
    expect(flagOf('tokyo'), findsOneWidget);
    expect(env.geo.lookups, isEmpty);
    expect(env.geo.downloads, isEmpty);
  });

  testWidgets('hosts without a flag icon are never looked up', (tester) async {
    await pumpApp(tester);
    await pumpUntil(tester, () => tester.any(flagOf('named')));
    expect(env.geo.lookups, isNot(contains('192.0.2.9')));
    expect(flagOf('plain'), findsNothing);
    expect(find.text('P'), findsOneWidget);
  });

  testWidgets('editor: pick a symbol and color, or a flag', (tester) async {
    await pumpApp(tester);
    await pumpUntil(tester, () => tester.any(flagOf('named')));

    // "plain" -> symbol "cloud" in red.
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('plain'), matching: find.byType(Card)),
        matching: find.byTooltip('编辑'),
      ),
    );
    await settleIo(tester);
    // Folded away under "More settings" at the bottom until opened.
    expect(find.byKey(const ValueKey('icon-kind')), findsNothing);
    await openMoreSettings(tester);
    await tester.tap(find.text('图标').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symbol-cloud')));
    await tester.pump();
    final red = find.byKey(ValueKey('color-${hostColorChoices[6]}'));
    await tester.ensureVisible(red);
    await tester.pumpAndSettle();
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('icon-preview')),
        matching: find.byIcon(Icons.cloud),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('保存'));
    await settleIo(tester);

    final card = find.ancestor(
      of: find.text('plain'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.cloud)),
      findsOneWidget,
    );
    final json = File('${env.dataDir.path}/hosts.json').readAsStringSync();
    expect(json, contains('"symbol": "cloud"'));
    expect(json, contains('"color": ${hostColorChoices[6]}'));

    // Switch it to a flag: the preview looks it up right away.
    env.geo.places['192.0.2.9'] = 'FR';
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('编辑')));
    await settleIo(tester);
    await openMoreSettings(tester);
    await tester.tap(find.text('国旗'));
    await pumpUntil(
      tester,
      () => tester.any(
        find.descendant(
          of: find.byKey(const ValueKey('icon-preview')),
          matching: find.byKey(const ValueKey('host-flag')),
        ),
      ),
    );
    expect(env.geo.lookups, contains('192.0.2.9'));
    await tester.tap(find.text('保存'));
    await settleIo(tester);
    expect(flagOf('plain'), findsOneWidget);
  });

  test('private address ranges', () {
    bool p(String s) => isPrivateAddress(InternetAddress(s));
    expect(p('10.1.2.3'), isTrue);
    expect(p('172.20.0.1'), isTrue);
    expect(p('172.32.0.1'), isFalse);
    expect(p('192.168.0.1'), isTrue);
    expect(p('100.64.1.1'), isTrue);
    expect(p('127.0.0.1'), isTrue);
    expect(p('fd00::1'), isTrue);
    expect(p('8.8.8.8'), isFalse);
    expect(p('2001:4860::8888'), isFalse);
  });
}
