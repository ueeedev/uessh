import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/l10n/l10n.dart';

import 'test_helpers.dart';

void main() {
  test('Chinese systems get Chinese, everything else English', () {
    expect(resolveAppLocale(const Locale('zh', 'CN')), const Locale('zh'));
    expect(resolveAppLocale(const Locale('zh', 'TW')), const Locale('zh'));
    expect(resolveAppLocale(const Locale('en', 'US')), const Locale('en'));
    expect(resolveAppLocale(const Locale('ja')), const Locale('en'));
    expect(resolveAppLocale(null), const Locale('en'));
  });

  test('both languages have exactly the same keys', () {
    Set<String> keys(String f) =>
        (jsonDecode(File(f).readAsStringSync()) as Map).keys
            .cast<String>()
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(keys('lib/l10n/app_en.arb'), keys('lib/l10n/app_zh.arb'));
  });

  testWidgets('switching to English changes the UI and is remembered', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    expect(find.text('还没有主机'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.text('Hosts').first);
    await tester.pumpAndSettle();
    expect(find.text('No hosts yet'), findsOneWidget);
    expect(find.text('New host'), findsOneWidget);
    // Text built outside widgets follows too.
    expect(currentL10n.loginCancelled, 'Login cancelled');

    await settleIo(tester);
    final saved = (await tester.runAsync(
      () => SettingsStore(dataDir: env.dataDir).load(),
    ))!;
    expect(saved.language, AppLanguage.en);
  });
}
