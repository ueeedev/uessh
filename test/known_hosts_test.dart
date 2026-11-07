import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/terminal/known_hosts.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  late KnownHostsStore store;
  late FakePrompts prompts;

  setUp(() {
    env = TestEnv();
    store = KnownHostsStore(dataDir: env.dataDir);
    prompts = FakePrompts();
  });
  tearDown(() => env.dispose());

  final keyA = Uint8List.fromList(List.generate(32, (i) => i));
  final keyB = Uint8List.fromList(List.generate(32, (i) => 255 - i));

  Future<bool> verify(Uint8List fp, {String type = 'ssh-ed25519'}) =>
      store.verify(
        address: 'Example.com',
        port: 22,
        keyType: type,
        fingerprint: fp,
        prompt: prompts.confirmHostKey,
      );

  test('formats fingerprints like OpenSSH', () {
    expect(
      formatFingerprint(keyA),
      'SHA256:AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
    );
  });

  test('asks on first connect, then remembers the key', () async {
    expect(await verify(keyA), isTrue);
    expect(prompts.hostKeyRequests, hasLength(1));
    expect(prompts.hostKeyRequests.single.hostPort, 'example.com:22');
    expect(prompts.hostKeyRequests.single.previous, isNull);

    expect(await verify(keyA), isTrue);
    expect(prompts.hostKeyRequests, hasLength(1), reason: 'no second prompt');
  });

  test('warns with the previous key when the key changes', () async {
    await verify(keyA);
    prompts.trustHostKey = false;

    expect(await verify(keyB), isFalse);
    final req = prompts.hostKeyRequests.last;
    expect(req.previous?.fingerprint, formatFingerprint(keyA));

    // Rejected, so the old key is still the trusted one.
    expect(await verify(keyA), isTrue);
    expect(prompts.hostKeyRequests, hasLength(2));
  });

  test('a different key type counts as a change', () async {
    await verify(keyA);
    await verify(keyA, type: 'ssh-rsa');
    expect(prompts.hostKeyRequests, hasLength(2));
    expect(prompts.hostKeyRequests.last.previous?.keyType, 'ssh-ed25519');
  });

  test('rejecting on first connect stores nothing', () async {
    prompts.trustHostKey = false;
    expect(await verify(keyA), isFalse);
    prompts.trustHostKey = true;
    await verify(keyA);
    expect(prompts.hostKeyRequests, hasLength(2));
  });
}
