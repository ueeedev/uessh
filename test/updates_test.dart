import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/settings/updates.dart';

import 'test_helpers.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('0.1.10', '0.1.9'), 1);
    expect(compareVersions('v0.2', '0.1.99'), 1);
    expect(compareVersions('0.1.5', 'v0.1.5'), 0);
    expect(compareVersions('0.1.5+6', '0.1.5'), 0);
    expect(compareVersions('0.1.4', '0.1.5'), -1);
    expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
  });

  test('the release page redirect gives the tag', () {
    expect(
      GitHubUpdateApi.tagFromUrl(
        'https://github.com/ueeedev/uessh/releases/tag/v0.1.4',
      ),
      'v0.1.4',
    );
    expect(
      GitHubUpdateApi.tagFromUrl('https://github.com/ueeedev/uessh/releases'),
      isNull,
    );
    expect(
      GitHubUpdateApi.tagFromUrl('https://evil.example/x/releases/tag/v9'),
      isNull,
    );
  });

  // The test app reports version 0.1.1 (see test_helpers).
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('check-updates')));
  }

  Future<AppSettings> saved(WidgetTester tester) async => (await tester
      .runAsync(() => SettingsStore(dataDir: env.dataDir).load()))!;

  final dialog = find.byKey(const ValueKey('update-dialog'));

  group('check for updates link', () {
    setUp(() => env.settings = env.settings.copyWith(autoCheckUpdates: false));

    testWidgets('sits under the version; new version: dialog', (tester) async {
      env.updates.version = '0.2.0';
      await pumpApp(tester);
      await openSettings(tester);
      final version = tester.getRect(find.byKey(const ValueKey('app-version')));
      final link = tester.getRect(find.byKey(const ValueKey('check-updates')));
      expect(link.top, greaterThanOrEqualTo(version.bottom));
      expect(find.text('检查更新'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await settleIo(tester);
      expect(dialog, findsOneWidget);
      expect(find.text('发现新版本 v0.2.0'), findsOneWidget);
      expect(find.textContaining('当前版本 v0.1.1'), findsOneWidget);
      expect(find.text('下次再说～'), findsOneWidget);
      expect(find.text('立刻前往'), findsOneWidget);
      expect(find.text('忽略此版本'), findsOneWidget);

      await tester.tap(find.text('下次再说～'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect((await saved(tester)).ignoredUpdateVersion, isNull);
    });

    testWidgets('ignore: remembered; the link still shows it', (tester) async {
      env.updates.version = '0.2.0';
      await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await settleIo(tester);
      await tester.tap(find.byKey(const ValueKey('update-ignore')));
      await settleIo(tester);
      expect((await saved(tester)).ignoredUpdateVersion, '0.2.0');

      // Asked by hand: shown anyway.
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await settleIo(tester);
      expect(dialog, findsOneWidget);
      await tester.tap(find.text('下次再说～'));
      await tester.pumpAndSettle();
    });

    testWidgets('up to date / offline: says so', (tester) async {
      env.updates.version = '0.1.1';
      await pumpApp(tester);
      await openSettings(tester);
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await settleIo(tester);
      expect(dialog, findsNothing);
      expect(find.text('已是最新版本（0.1.1）'), findsOneWidget);

      env.updates.fail = true;
      await tester.pump(const Duration(seconds: 5)); // snack bar gone
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await settleIo(tester);
      expect(find.text('检查更新失败，请稍后再试'), findsOneWidget);
    });

    testWidgets('the auto-check switch is saved', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('auto-check-updates'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await settleIo(tester);
      expect((await saved(tester)).autoCheckUpdates, isTrue);
    });
  });

  group('at startup', () {
    testWidgets('on: a new version pops up by itself', (tester) async {
      env.updates.version = '0.1.2';
      await pumpApp(tester);
      expect(dialog, findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await settleIo(tester);
      expect(dialog, findsOneWidget);
      expect(env.updates.checks, 1);
      await tester.tap(find.text('下次再说～'));
      await tester.pumpAndSettle();
    });

    testWidgets('on, nothing new: silent', (tester) async {
      env.updates.version = '0.1.1';
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await settleIo(tester);
      expect(env.updates.checks, 1);
      expect(dialog, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('ignored version: silent; a newer one shows again', (
      tester,
    ) async {
      env.settings = env.settings.copyWith(ignoredUpdateVersion: '0.2.0');
      env.updates.version = '0.2.0';
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await settleIo(tester);
      expect(env.updates.checks, 1);
      expect(dialog, findsNothing);
    });

    testWidgets('ignored, then a newer release: shown', (tester) async {
      env.settings = env.settings.copyWith(ignoredUpdateVersion: '0.2.0');
      env.updates.version = '0.2.1';
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 3));
      await settleIo(tester);
      expect(dialog, findsOneWidget);
      expect(find.text('发现新版本 v0.2.1'), findsOneWidget);
      await tester.tap(find.text('下次再说～'));
      await tester.pumpAndSettle();
    });

    testWidgets('off: no check at all', (tester) async {
      env.settings = env.settings.copyWith(autoCheckUpdates: false);
      env.updates.version = '9.9.9';
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 5));
      await settleIo(tester);
      expect(env.updates.checks, 0);
      expect(dialog, findsNothing);
    });
  });

  test('settings: update fields round-trip', () {
    final s = const AppSettings().copyWith(
      autoCheckUpdates: false,
      ignoredUpdateVersion: '0.3.0',
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.autoCheckUpdates, isFalse);
    expect(back.ignoredUpdateVersion, '0.3.0');
    expect(const AppSettings().autoCheckUpdates, isTrue);
  });
}
