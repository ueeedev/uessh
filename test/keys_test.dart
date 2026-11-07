import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/keys/keys_page.dart';
import 'package:uessh/features/keys/ssh_key.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';
import 'package:uessh/widgets/app_dropdown.dart';

import 'fixture_keys.dart';
import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('inspectPrivateKey', () {
    test('reads type, fingerprint and public key', () async {
      final info = await inspectPrivateKey(fixtureKey, null, comment: 'laptop');
      expect(info.keyType, 'ssh-ed25519');
      expect(
        info.fingerprint,
        fixtureFingerprint,
        reason: 'same as ssh-keygen -l',
      );
      expect(info.publicKey, 'ssh-ed25519 $fixturePublicBlob laptop');
    });

    test('encrypted: works with the passphrase, accepted without it', () async {
      final info = await inspectPrivateKey(fixtureEncryptedKey, 'testpass');
      expect(info.keyType, 'ssh-ed25519');
      final noPass = await inspectPrivateKey(fixtureEncryptedKey, '');
      expect(noPass.keyType, isNull, reason: 'asked on connect instead');
      expect(
        () => inspectPrivateKey(fixtureEncryptedKey, 'wrong'),
        throwsA(isA<InvalidKeyException>()),
      );
    });

    test('rejects empty and garbage input', () {
      expect(
        () => inspectPrivateKey('  ', null),
        throwsA(isA<InvalidKeyException>()),
      );
      expect(
        () => inspectPrivateKey('not a key', null),
        throwsA(isA<InvalidKeyException>()),
      );
    });
  });

  test('key list on disk never contains the private key', () async {
    final repo = KeyRepository(dataDir: env.dataDir, secrets: env.secrets);
    await repo.save([const SshKey(id: 'k', name: 'n', keyType: 'ssh-ed25519')]);
    await repo.writeSecrets('k', const KeySecrets(privateKey: fixtureKey));
    final json = File('${env.dataDir.path}/keys.json').readAsStringSync();
    expect(json, isNot(contains('PRIVATE KEY')));
    expect((await repo.load()).single.name, 'n');
    expect((await repo.readSecrets('k')).privateKey, fixtureKey);
    await repo.deleteSecrets('k');
    expect(env.secrets.values, isEmpty);
  });

  group('sessions with a saved key', () {
    Future<TerminalSession> connect(Host host, KeyRepository keys) async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final s = TerminalSession(
        host: host.copyWith(port: port),
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
        keys: keys,
      );
      await s.connect();
      return s;
    }

    const host = Host(
      id: 'h',
      label: '',
      address: '127.0.0.1',
      port: 22,
      username: 'u',
      authMethod: AuthMethod.key,
      keyId: 'k',
    );

    test('loads the saved key before connecting', () async {
      final keys = KeyRepository(dataDir: env.dataDir, secrets: env.secrets);
      await keys.writeSecrets('k', const KeySecrets(privateKey: fixtureKey));
      final s = await connect(host, keys);
      // Got past key loading; failed only because nothing listens.
      expect(s.error, contains('无法连接到'));
      s.dispose();
    });

    test('a deleted key gives a clear message', () async {
      final keys = KeyRepository(dataDir: env.dataDir, secrets: env.secrets);
      final s = await connect(host, keys);
      expect(s.error, contains('密钥已被删除'));
      s.dispose();
    });
  });

  group('keys page', () {
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);
      await tester.tap(find.text('密钥'));
      await tester.pumpAndSettle();
    }

    testWidgets('add, edit and delete a key in the side sheet', (tester) async {
      await pumpApp(tester);
      expect(find.text('还没有密钥'), findsOneWidget);

      await tester.tap(find.text('添加密钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入名称'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, '名称'), '工作笔记本');
      await tester.enterText(find.widgetWithText(TextField, '私钥'), 'garbage');
      await tester.tap(find.text('保存'));
      await pumpUntil(
        tester,
        () => find.textContaining('无法识别私钥格式').evaluate().isNotEmpty,
      );

      await tester.enterText(find.widgetWithText(TextField, '私钥'), fixtureKey);
      await tester.tap(find.text('保存'));
      await pumpUntil(tester, () => find.byType(KeyCard).evaluate().isNotEmpty);
      expect(find.text('工作笔记本'), findsOneWidget);
      expect(find.textContaining('ED25519'), findsOneWidget);
      expect(
        File('${env.dataDir.path}/keys.json').readAsStringSync(),
        isNot(contains('PRIVATE KEY')),
      );

      // Edit shows the fingerprint and can copy the public key.
      await tester.tap(find.byTooltip('编辑'));
      await settleIo(tester);
      expect(find.text('编辑密钥'), findsOneWidget);
      expect(find.text(fixtureFingerprint), findsOneWidget);
      expect(find.text('复制公钥'), findsOneWidget);

      // Delete asks first.
      await tester.tap(find.byKey(const ValueKey('delete-key')));
      await tester.pumpAndSettle();
      expect(find.text('删除密钥“工作笔记本”？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settleIo(tester);
      expect(find.text('还没有密钥'), findsOneWidget);
      expect(env.secrets.values, isEmpty);
    });

    testWidgets('a host can use a saved key instead of pasting one', (
      tester,
    ) async {
      final repo = KeyRepository(dataDir: env.dataDir, secrets: env.secrets);
      await tester.runAsync(() async {
        await repo.save([
          const SshKey(id: 'k1', name: '工作笔记本', keyType: 'ssh-ed25519'),
        ]);
        await repo.writeSecrets('k1', const KeySecrets(privateKey: fixtureKey));
      });
      await pumpApp(tester);
      await tester.tap(find.text('主机'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('新建主机'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '地址'),
        '10.0.0.7',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'root');
      await tester.tap(find.text('私钥').first);
      await tester.pumpAndSettle();

      // Pasting is the default; picking the saved key hides the paste box.
      expect(find.widgetWithText(TextField, '私钥口令'), findsOneWidget);
      await tester.tap(find.byType(AppDropdown<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('工作笔记本').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '私钥口令'), findsNothing);

      await tester.tap(find.text('保存'));
      await settleIo(tester);
      final json = File('${env.dataDir.path}/hosts.json').readAsStringSync();
      expect(json, contains('"keyId": "k1"'));
      expect(
        env.secrets.values.keys.where((k) => k.startsWith('uessh.host.')),
        isEmpty,
        reason: 'no pasted key stored for the host',
      );
    });
  });
}
