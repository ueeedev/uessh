import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  late HostRepository repo;

  setUp(() {
    env = TestEnv();
    repo = HostRepository(dataDir: env.dataDir, secrets: env.secrets);
  });
  tearDown(() => env.dispose());

  TerminalSession sessionFor(Host host, FakePrompts prompts) => TerminalSession(
    host: host,
    repository: repo,
    knownHosts: KnownHostsStore(dataDir: env.dataDir),
    prompts: prompts,
  );

  test(
    'refused connection ends in failed state with a readable error',
    () async {
      // Grab a free port, then close it so nothing is listening there.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      final session = sessionFor(
        Host(
          id: 'h',
          label: '',
          address: '127.0.0.1',
          port: port,
          username: 'u',
          authMethod: AuthMethod.password,
        ),
        FakePrompts(),
      );
      await session.connect();

      expect(session.status, SessionStatus.failed);
      expect(session.error, contains('无法连接到 127.0.0.1:$port'));
      session.dispose();
    },
  );

  test('key auth without a saved key fails before connecting', () async {
    final session = sessionFor(
      const Host(
        id: 'k',
        label: '',
        address: '127.0.0.1',
        port: 22,
        username: 'u',
        authMethod: AuthMethod.key,
      ),
      FakePrompts(),
    );
    await session.connect();

    expect(session.status, SessionStatus.failed);
    expect(session.error, contains('没有保存私钥'));
    session.dispose();
  });

  group('auto-reconnect', () {
    Future<Host> deadHost() async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      return Host(
        id: 'r',
        label: '',
        address: '127.0.0.1',
        port: port,
        username: 'u',
        authMethod: AuthMethod.password,
      );
    }

    String screen(TerminalSession s) =>
        s.terminal.buffer.lines.toList().map((l) => l.toString()).join('\n');

    test('a drop retries N times, then gives up', () async {
      final session = sessionFor(await deadHost(), FakePrompts());
      session.reconnectPolicy = () =>
          (enabled: true, attempts: 2, delay: const Duration(milliseconds: 20));
      session.debugConnectionDropped();
      expect(session.reconnectPending, isTrue);
      expect(session.reconnectAttempt, 1);
      expect(session.reconnectTotal, 2);

      // Each attempt hits the closed port and plans the next.
      for (var i = 0; i < 100 && session.reconnectAttempt != 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(session.reconnectAttempt, 0);
      expect(session.reconnectPending, isFalse);
      expect(session.status, SessionStatus.failed);
      final text = screen(session);
      expect(text, contains('第 1/2 次'));
      expect(text, contains('第 2/2 次'));
      expect(text, contains('已重连 2 次仍未成功'));
      session.dispose();
    });

    test('turned off: a drop just stays closed', () async {
      final session = sessionFor(await deadHost(), FakePrompts());
      session.reconnectPolicy = () =>
          (enabled: false, attempts: 3, delay: Duration.zero);
      session.debugConnectionDropped();
      expect(session.reconnectPending, isFalse);
      expect(session.status, SessionStatus.closed);
      session.dispose();
    });

    test('cancel, close and a manual connect stop the countdown', () async {
      final session = sessionFor(await deadHost(), FakePrompts());
      session.reconnectPolicy = () =>
          (enabled: true, attempts: 3, delay: const Duration(seconds: 30));
      session.debugConnectionDropped();
      expect(session.reconnectPending, isTrue);
      session.cancelReconnect();
      expect(session.reconnectPending, isFalse);
      expect(session.reconnectAttempt, 0);

      session.debugConnectionDropped();
      session.close();
      expect(session.reconnectPending, isFalse);

      // A manual connect that fails doesn't start retrying.
      session.debugConnectionDropped();
      await session.connect();
      expect(session.status, SessionStatus.failed);
      expect(session.reconnectPending, isFalse);
      expect(session.reconnectAttempt, 0);
      session.dispose();
    });

    test('wrong password is not retried', () async {
      // Covered by _worthRetrying: auth errors stop the round.
      final session = sessionFor(
        const Host(
          id: 'k',
          label: '',
          address: '127.0.0.1',
          port: 22,
          username: 'u',
          authMethod: AuthMethod.key,
        ),
        FakePrompts(),
      );
      session.reconnectPolicy = () =>
          (enabled: true, attempts: 3, delay: const Duration(milliseconds: 10));
      session.debugConnectionDropped();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // "No saved key" fails the same way as a refused login.
      expect(session.reconnectPending, isFalse);
      expect(session.reconnectAttempt, 0);
      session.dispose();
    });
  });
}
