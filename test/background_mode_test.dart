import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/l10n/l10n.dart';
import 'package:uessh/shell/background_mode.dart';

import 'test_helpers.dart';

Host host(int i) => Host(
  id: 'h$i',
  label: 'host-$i',
  address: '10.0.0.$i',
  port: 22,
  username: 'u',
  authMethod: AuthMethod.password,
);

void main() {
  group('tray menu', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    final en = lookupAppLocalizations(const Locale('en'));

    test('show, quick connect (one item per host), quit', () {
      Host? connected;
      var shown = false, quit = false;
      final menu = TrayMenuModel(l: zh, hosts: [host(1), host(2)]).build(
        onShow: () => shown = true,
        onConnect: (h) => connected = h,
        onQuit: () => quit = true,
      );
      final items = menu.items!;
      expect(items.map((i) => i.label).whereType<String>(), [
        '显示 uessh',
        '快速连接',
        '退出 uessh',
      ]);
      final hosts = items[2].submenu!.items!;
      expect(hosts.map((i) => i.label), ['host-1', 'host-2']);

      items[0].onClick!(items[0]);
      hosts[1].onClick!(hosts[1]);
      items.last.onClick!(items.last);
      expect(shown, isTrue);
      expect(connected?.id, 'h2');
      expect(quit, isTrue);
    });

    test('English labels; long host lists are capped', () {
      final menu = TrayMenuModel(
        l: en,
        hosts: [for (var i = 0; i < 40; i++) host(i)],
      ).build(onShow: () {}, onConnect: (_) {}, onQuit: () {});
      expect(menu.items!.first.label, 'Show uessh');
      expect(menu.items!.last.label, 'Quit uessh');
      expect(menu.items![2].submenu!.items!.length, TrayMenuModel.maxHosts);
    });

    test('no hosts: quick connect is disabled with a hint', () {
      final menu = TrayMenuModel(
        l: zh,
        hosts: const [],
      ).build(onShow: () {}, onConnect: (_) {}, onQuit: () {});
      final quick = menu.items![2];
      expect(quick.disabled, isTrue);
      expect(quick.submenu!.items!.single.label, '还没有主机');
    });
  });

  testWidgets('"keep running in background" is on by default and saved', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    expect(const AppSettings().runInBackground, isTrue);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('run-in-background'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await settleIo(tester);
    final saved = (await tester.runAsync(
      () => SettingsStore(dataDir: env.dataDir).load(),
    ))!;
    expect(saved.runInBackground, isFalse);
  });
}
