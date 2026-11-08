import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/core/vault.dart';
import 'package:uessh/features/security/lock_screen.dart';
import 'package:uessh/features/security/vault_controller.dart';
import 'package:uessh/widgets/side_sheet.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  final lockTitle = find.text('uessh 已锁定');
  final lockField = find.descendant(
    of: find.byType(LockScreen),
    matching: find.byType(TextField),
  );

  /// Real vault in the test's data dir, fast KDF.
  Future<Vault> realVault(WidgetTester tester, {String? password}) async {
    return (await tester.runAsync(() async {
      final v = (await Vault.open(env.dataDir)).vault
        ..kdfMemoryKiB = 1024
        ..kdfIterations = 1;
      await v.write('uessh.host.a.password', 'host-pw');
      if (password != null) {
        await v.setPassword(password);
        final reopened = (await Vault.open(env.dataDir)).vault
          ..kdfMemoryKiB = 1024
          ..kdfIterations = 1;
        return reopened; // locked
      }
      return v;
    }))!;
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
  }

  testWidgets('no master password: no lock screen at all', (tester) async {
    env.vault = await realVault(tester);
    await pumpApp(tester);
    expect(lockTitle, findsNothing);
    expect(find.text('还没有主机'), findsOneWidget);
  });

  testWidgets('with a master password the app starts locked', (tester) async {
    env.vault = await realVault(tester, password: 'pw-123456');
    await pumpApp(tester);
    expect(lockTitle, findsOneWidget);

    await tester.enterText(lockField, 'wrong-pass');
    await tester.tap(find.text('解锁'));
    await pumpUntil(tester, () => find.text('主密码不正确').evaluate().isNotEmpty);
    expect(lockTitle, findsOneWidget);

    await tester.enterText(lockField, 'pw-123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntil(tester, () => lockTitle.evaluate().isEmpty);
    expect(find.text('还没有主机'), findsOneWidget);
    expect(env.vault.read('uessh.host.a.password'), 'host-pw');
  });

  testWidgets('forgot password: reset wipes secrets and unlocks', (
    tester,
  ) async {
    env.vault = await realVault(tester, password: 'pw-123456');
    await pumpApp(tester);
    await tester.tap(find.text('忘记主密码？'));
    await tester.pumpAndSettle();
    expect(find.text('重置保险库？'), findsOneWidget);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(lockTitle, findsOneWidget);

    await tester.tap(find.text('忘记主密码？'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除已保存的凭据并重置'));
    await pumpUntil(tester, () => lockTitle.evaluate().isEmpty);
    expect(env.vault.mode, VaultMode.local);
    expect(env.vault.read('uessh.host.a.password'), isNull);
  });

  testWidgets('turn master password on, lock now, unlock, turn it off', (
    tester,
  ) async {
    env.vault = await realVault(tester);
    await pumpApp(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // On: validation first.
    await tester.tap(find.widgetWithText(SwitchListTile, '主密码'));
    await tester.pumpAndSettle();
    expect(find.text('设置主密码'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '主密码'), 'short');
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();
    expect(find.text('至少 8 个字符'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextFormField, '主密码'),
      'pw-123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '再输入一次'),
      'pw-1234567',
    );
    await tester.tap(find.text('开启'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入不一致'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '再输入一次'),
      'pw-123456',
    );
    await tester.tap(find.text('开启'));
    await pumpUntil(tester, () => find.text('设置主密码').evaluate().isEmpty);
    expect(env.vault.mode, VaultMode.password);
    expect(File('${env.dataDir.path}/vault.key').existsSync(), isFalse);
    expect(find.text('修改主密码'), findsOneWidget);

    // Lock now, then unlock.
    await tester.ensureVisible(find.text('立即锁定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即锁定'));
    await tester.pumpAndSettle();
    expect(lockTitle, findsOneWidget);
    await tester.enterText(lockField, 'pw-123456');
    await tester.tap(find.text('解锁'));
    await pumpUntil(tester, () => lockTitle.evaluate().isEmpty);

    // Off: needs the current password.
    await tester.tap(find.widgetWithText(SwitchListTile, '主密码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '当前主密码'), 'nope');
    await tester.tap(find.widgetWithText(FilledButton, '关闭主密码'));
    await pumpUntil(tester, () => find.text('主密码不正确').evaluate().isNotEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, '当前主密码'),
      'pw-123456',
    );
    await tester.tap(find.widgetWithText(FilledButton, '关闭主密码'));
    await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);
    expect(env.vault.mode, VaultMode.local);
    expect(env.vault.read('uessh.host.a.password'), 'host-pw');
  });

  testWidgets('locks after the idle time; activity postpones it', (
    tester,
  ) async {
    env.vault = await realVault(tester, password: 'pw-123456');
    await tester.runAsync(() => env.vault.unlock('pw-123456'));
    await pumpApp(tester);
    expect(lockTitle, findsNothing);

    // Default: 15 minutes.
    await tester.pump(const Duration(minutes: 10));
    await tester.tap(find.text('设置')); // activity
    await tester.pump(const Duration(minutes: 10));
    expect(lockTitle, findsNothing, reason: 'timer restarted by the tap');
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(lockTitle, findsOneWidget);
  });

  testWidgets('the lock screen covers open side sheets', (tester) async {
    env.vault = await realVault(tester, password: 'pw-123456');
    await tester.runAsync(() => env.vault.unlock('pw-123456'));
    await pumpApp(tester);
    await tester.tap(find.text('新建主机'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '地址'), '1.2.3.4');
    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'u');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VaultGate)),
    );
    container.read(vaultControllerProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(lockTitle, findsOneWidget);

    // The sheet is still there underneath (state kept) but can't be used.
    expect(find.byType(SideSheet), findsOneWidget);
    await tester.tap(find.text('保存'), warnIfMissed: false);
    await settleIo(tester);
    expect(File('${env.dataDir.path}/hosts.json').existsSync(), isFalse);
  });
}
