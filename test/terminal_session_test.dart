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
}
