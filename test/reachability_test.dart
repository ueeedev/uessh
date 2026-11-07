import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/hosts_page.dart';
import 'package:uessh/features/hosts/reachability.dart';
import 'package:uessh/features/settings/app_settings.dart';

import 'test_helpers.dart';

void main() {
  group('AppSettings', () {
    test('round-trips through JSON', () {
      const s = AppSettings(
        themeMode: ThemeMode.dark,
        followSystemAccent: false,
        checkIntervalSeconds: 60,
        checkMethod: ReachabilityMethod.sshPort,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
    });

    test('bad values fall back to defaults', () {
      final s = AppSettings.fromJson({
        'themeMode': 'purple',
        'checkIntervalSeconds': 1,
        'checkMethod': 'carrier-pigeon',
      });
      expect(s.themeMode, ThemeMode.system);
      expect(s.checkIntervalSeconds, 30);
      expect(s.checkMethod, ReachabilityMethod.ping);
    });

    test('store survives a corrupt file', () async {
      final env = TestEnv();
      addTearDown(env.dispose);
      File('${env.dataDir.path}/settings.json').writeAsStringSync('{oops');
      final s = await SettingsStore(dataDir: env.dataDir).load();
      expect(s.checkIntervalSeconds, 30);
    });
  });

  group('SystemReachabilityChecker', () {
    final checker = SystemReachabilityChecker();
    Host hostAt(String address, int port) => Host(
      id: 'x',
      label: '',
      address: address,
      port: port,
      username: 'u',
      authMethod: AuthMethod.password,
    );

    test('SSH-port mode: open port is up, closed port is down', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((s) => s.destroy());
      expect(
        await checker.check(
          hostAt('127.0.0.1', server.port),
          ReachabilityMethod.sshPort,
        ),
        isNotNull,
      );

      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      expect(
        await checker.check(
          hostAt('127.0.0.1', port),
          ReachabilityMethod.sshPort,
        ),
        isNull,
      );
    });

    test('ping mode: localhost answers, an unused address does not', () async {
      final up = await checker.check(
        hostAt('127.0.0.1', 22),
        ReachabilityMethod.ping,
      );
      expect(up, isNotNull);
      expect(up!.inMilliseconds, lessThan(1000));

      expect(
        await checker.check(
          // TEST-NET-1: reserved for documentation, never answers.
          hostAt('192.0.2.1', 22),
          ReachabilityMethod.ping,
        ),
        isNull,
      );
    });
  });

  group('host status dots', () {
    late TestEnv env;
    setUp(() {
      env = TestEnv();
      File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,"groups":[],"hosts":[
 {"id":"a","label":"up-host","address":"10.0.0.1","port":22,"username":"root","authMethod":"password"},
 {"id":"b","label":"down-host","address":"10.0.0.2","port":22,"username":"root","authMethod":"password"}
]}''');
      env.reachability.up['10.0.0.1'] = const Duration(milliseconds: 12);
    });
    tearDown(() => env.dispose());

    Future<void> pumpApp(WidgetTester tester, {AppSettings? settings}) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);
    }

    Finder dotOf(String hostName) => find.descendant(
      of: find.ancestor(
        of: find.text(hostName),
        matching: find.byType(HostCard),
      ),
      matching: find.byType(ReachabilityDot),
    );

    Color colorOf(WidgetTester tester, String hostName) {
      final box = tester.widget<Container>(
        find.descendant(of: dotOf(hostName), matching: find.byType(Container)),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('green when reachable, red when not; checked at launch', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(colorOf(tester, 'up-host'), const Color(0xFF34C759));
      expect(colorOf(tester, 'down-host'), const Color(0xFFFF3B30));
      expect(env.reachability.callsFor('10.0.0.1'), 1);
      expect(env.reachability.calls.first.method, ReachabilityMethod.ping);

      // The dot sits left of the name; user and address are not shown.
      final dot = tester.getRect(dotOf('up-host'));
      final name = tester.getRect(find.text('up-host'));
      expect(dot.right, lessThan(name.left));
      expect((dot.center.dy - name.center.dy).abs(), lessThan(2));
      expect(find.textContaining('root@'), findsNothing);
      expect(find.textContaining('10.0.0.1'), findsNothing);
    });

    testWidgets('re-checks every 30 seconds by default', (tester) async {
      await pumpApp(tester);
      expect(env.reachability.callsFor('10.0.0.2'), 1);

      await tester.pump(const Duration(seconds: 29));
      expect(env.reachability.callsFor('10.0.0.2'), 1);
      await tester.pump(const Duration(seconds: 1));
      expect(env.reachability.callsFor('10.0.0.2'), 2);

      // A host coming back online turns green on the next round.
      env.reachability.up['10.0.0.2'] = const Duration(milliseconds: 5);
      await tester.pump(const Duration(seconds: 30));
      expect(colorOf(tester, 'down-host'), const Color(0xFF34C759));
    });

    testWidgets('interval and method set in settings take effect and persist', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('check-interval')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 秒').last);
      await tester.pumpAndSettle();

      final before = env.reachability.callsFor('10.0.0.1');
      await tester.pump(const Duration(seconds: 10));
      expect(env.reachability.callsFor('10.0.0.1'), before + 1);

      // Switching method re-checks right away with the new method.
      await tester.tap(find.text('SSH 端口'));
      await tester.pump();
      expect(env.reachability.calls.last.method, ReachabilityMethod.sshPort);

      await settleIo(tester);
      // Real file I/O must run outside the fake test clock.
      final saved = (await tester.runAsync(
        () => SettingsStore(dataDir: env.dataDir).load(),
      ))!;
      expect(saved.checkIntervalSeconds, 10);
      expect(saved.checkMethod, ReachabilityMethod.sshPort);
    });
  });
}
