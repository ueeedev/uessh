import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/core/secret_store.dart';
import 'package:uessh/core/vault.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('uessh_vault_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String vaultJson() => File('${dir.path}/vault.json').readAsStringSync();
  File keyFile() => File('${dir.path}/vault.key');

  test('a new vault is local, unlocked, and survives reopening', () async {
    final first = await Vault.open(dir);
    expect(first.created, isTrue);
    expect(first.vault.mode, VaultMode.local);
    await first.vault.write('k', 's3cret-value');

    final again = await Vault.open(dir);
    expect(again.created, isFalse);
    expect(again.vault.isUnlocked, isTrue, reason: 'local: no prompt');
    expect(again.vault.read('k'), 's3cret-value');
  });

  test('secrets never appear in plain text on disk', () async {
    final v = (await Vault.open(dir)).vault;
    await v.write('k', 's3cret-value');
    expect(vaultJson(), isNot(contains('s3cret')));
    expect(
      vaultJson(),
      isNot(contains(base64.encode(utf8.encode('s3cret-value')))),
    );
  });

  test('a tampered file is rejected', () async {
    final v = (await Vault.open(dir)).vault;
    await v.write('k', 'v');
    final json = jsonDecode(vaultJson()) as Map;
    final data = base64.decode(json['entries']['data'] as String);
    data[0] ^= 1;
    json['entries']['data'] = base64.encode(data);
    File('${dir.path}/vault.json').writeAsStringSync(jsonEncode(json));
    expect(() => Vault.open(dir), throwsA(anything));
  });

  test('rapid writes all land, latest value wins', () async {
    final v = (await Vault.open(dir)).vault;
    await Future.wait([for (var i = 0; i < 20; i++) v.write('k$i', 'v$i')]);
    await v.write('k0', 'last');
    final again = (await Vault.open(dir)).vault;
    expect(again.read('k19'), 'v19');
    expect(again.read('k0'), 'last');
  });

  test('empty value deletes an entry', () async {
    final v = (await Vault.open(dir)).vault;
    await v.write('k', 'v');
    await v.write('k', '');
    expect((await Vault.open(dir)).vault.read('k'), isNull);
  });

  group('master password', () {
    test(
      'setting it removes the key file; reopening needs the password',
      () async {
        final v = (await Vault.open(dir)).vault;
        await v.write('k', 'v');
        await v.setPassword('pw-123456');
        expect(keyFile().existsSync(), isFalse);
        expect(v.isUnlocked, isTrue, reason: 'stays open in this session');

        final again = (await Vault.open(dir)).vault;
        expect(again.mode, VaultMode.password);
        expect(again.isUnlocked, isFalse);
        expect(() => again.read('k'), throwsA(isA<VaultLockedException>()));
        await expectLater(
          again.unlock('wrong'),
          throwsA(isA<WrongPasswordException>()),
        );
        await again.unlock('pw-123456');
        expect(again.read('k'), 'v');
      },
    );

    test('lock forgets everything until unlocked again', () async {
      final v = (await Vault.open(dir)).vault;
      await v.setPassword('pw-123456');
      await v.write('k', 'v');
      v.lock();
      expect(v.isUnlocked, isFalse);
      expect(() => v.write('k', 'x'), throwsA(isA<VaultLockedException>()));
      await v.unlock('pw-123456');
      expect(v.read('k'), 'v');
    });

    test('change password: old one stops working', () async {
      final v = (await Vault.open(dir)).vault;
      await v.setPassword('old-pass');
      await v.write('k', 'v');
      await expectLater(
        v.changePassword('nope', 'new-pass'),
        throwsA(isA<WrongPasswordException>()),
      );
      await v.changePassword('old-pass', 'new-pass');

      final again = (await Vault.open(dir)).vault;
      await expectLater(
        again.unlock('old-pass'),
        throwsA(isA<WrongPasswordException>()),
      );
      await again.unlock('new-pass');
      expect(again.read('k'), 'v');
    });

    test('removing it needs the current password and keeps the data', () async {
      final v = (await Vault.open(dir)).vault;
      await v.write('k', 'v');
      await v.setPassword('pw-123456');
      await expectLater(
        v.removePassword('nope'),
        throwsA(isA<WrongPasswordException>()),
      );
      await v.removePassword('pw-123456');
      expect(keyFile().existsSync(), isTrue);

      final again = (await Vault.open(dir)).vault;
      expect(again.mode, VaultMode.local);
      expect(again.isUnlocked, isTrue);
      expect(again.read('k'), 'v');
    });

    test('reset wipes secrets and goes back to an open local vault', () async {
      final v = (await Vault.open(dir)).vault;
      await v.write('k', 'v');
      await v.setPassword('pw-123456');
      final locked = (await Vault.open(dir)).vault;
      await locked.reset();
      expect(locked.isUnlocked, isTrue);
      expect(locked.read('k'), isNull);
      expect((await Vault.open(dir)).vault.mode, VaultMode.local);
    });
  });

  test('migration moves keychain entries and removes them there', () async {
    final keychain = MemorySecretStore()
      ..values['a'] = '1'
      ..values['b'] = '2';
    final v = (await Vault.open(dir)).vault;
    final moved = await migrateKeychainSecrets(
      keychain: keychain,
      vault: v,
      keys: ['a', 'b', 'missing'],
    );
    expect(moved, 2);
    expect(v.read('a'), '1');
    expect(v.read('b'), '2');
    expect(keychain.values, isEmpty);
  });

  test('migration skips entries it cannot read and leaves them', () async {
    final keychain = _DenyingStore({'a': '1', 'deny': 'x'});
    final v = (await Vault.open(dir)).vault;
    final moved = await migrateKeychainSecrets(
      keychain: keychain,
      vault: v,
      keys: ['deny', 'a'],
    );
    expect(moved, 1);
    expect(v.read('a'), '1');
    expect(keychain.values.containsKey('deny'), isTrue);
  });
}

class _DenyingStore extends MemorySecretStore {
  _DenyingStore(Map<String, String> initial) {
    values.addAll(initial);
  }

  @override
  Future<String?> read(String key) async {
    if (key == 'deny') throw Exception('user denied access');
    return super.read(key);
  }
}
