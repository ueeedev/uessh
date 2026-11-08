import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/hosts_page.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() {
    env = TestEnv();
    File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[],"hosts":[
 {"id":"a","label":"alpha","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"},
 {"id":"b","label":"bravo","address":"127.0.0.1","port":1,"username":"u","authMethod":"password"}
]}''');
  });
  tearDown(() => env.dispose());

  testWidgets('host card: click selects, double-click connects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(UesshApp)));
    // Clicks with explicit times (test pointers default to time zero).
    var clock = const Duration(seconds: 10);
    Future<void> click(String label, {int afterMs = 1000}) async {
      clock += Duration(milliseconds: afterMs);
      final g = await tester.createGesture();
      await g.down(tester.getCenter(find.text(label)), timeStamp: clock);
      await g.up(timeStamp: clock + const Duration(milliseconds: 50));
      await tester.pump();
    }

    HostCard card(String label) => tester.widget<HostCard>(
      find.ancestor(of: find.text(label), matching: find.byType(HostCard)),
    );

    // One click: selected right away (no wait for a second click),
    // nothing opened.
    await click('alpha');
    expect(card('alpha').selected, isTrue);
    expect(card('bravo').selected, isFalse);
    expect(c.read(sessionsProvider).sessions, isEmpty);

    // Clicking another moves the selection.
    await click('bravo');
    expect(card('alpha').selected, isFalse);
    expect(card('bravo').selected, isTrue);

    // Two clicks a while apart: still just selected.
    await click('alpha');
    await click('alpha', afterMs: 900);
    expect(c.read(sessionsProvider).sessions, isEmpty);
    expect(card('alpha').selected, isTrue);

    // Double-click: opens SSH and shows the terminal page.
    await click('alpha');
    await click('alpha', afterMs: 250);
    await settleIo(tester);
    await tester.pumpAndSettle();
    final sessions = c.read(sessionsProvider).sessions;
    expect(sessions, hasLength(1));
    expect(sessions.single.host.id, 'a');
    expect(find.byKey(const ValueKey('tab-strip')), findsOneWidget);
  });
}
