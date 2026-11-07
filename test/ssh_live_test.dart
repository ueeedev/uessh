// Connects to a real SSH server. Skipped unless these are set:
//   UESSH_TEST_HOST, UESSH_TEST_USER, UESSH_TEST_PASSWORD
//   UESSH_TEST_PORT (optional, default 22)
// Optional key auth: UESSH_TEST_KEY_FILE (+ UESSH_TEST_KEY_PASSPHRASE).
// Only runs harmless `echo` commands on the server.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/server_stats.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

final _env = Platform.environment;
final _host = _env['UESSH_TEST_HOST'];
final _user = _env['UESSH_TEST_USER'];
final _password = _env['UESSH_TEST_PASSWORD'];
final _port = int.tryParse(_env['UESSH_TEST_PORT'] ?? '') ?? 22;
final _keyFile = _env['UESSH_TEST_KEY_FILE'];

void main() {
  final skipPassword = (_host == null || _user == null || _password == null)
      ? 'set UESSH_TEST_HOST / USER / PASSWORD to run'
      : false;

  late TestEnv env;
  late HostRepository repo;
  late KnownHostsStore knownHosts;

  setUp(() {
    env = TestEnv();
    repo = HostRepository(dataDir: env.dataDir, secrets: env.secrets);
    knownHosts = KnownHostsStore(dataDir: env.dataDir);
  });
  tearDown(() => env.dispose());

  Host hostWith(AuthMethod method) => Host(
    id: 'live-${method.name}',
    label: 'live',
    address: _host ?? '',
    port: _port,
    username: _user ?? '',
    authMethod: method,
  );

  TerminalSession sessionFor(Host host, FakePrompts prompts) => TerminalSession(
    host: host,
    repository: repo,
    knownHosts: knownHosts,
    prompts: prompts,
  );

  /// Polls the terminal buffer until [text] shows up.
  Future<void> waitForText(TerminalSession s, String text) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!s.terminal.buffer.getText().contains(text)) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'timed out waiting for "$text". Buffer:\n'
          '${s.terminal.buffer.getText()}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Types a command and checks its computed output appears. The marker is
  /// built by the shell (`$((...))`) so the echoed command line can't match.
  Future<void> runEcho(TerminalSession s) async {
    s.terminal.textInput(
      r'echo uessh-$((40+2))-ok'
      '\r',
    );
    await waitForText(s, 'uessh-42-ok');
  }

  test(
    'password login opens a working shell',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final prompts = FakePrompts();
      final s = sessionFor(host, prompts);

      await s.connect();
      expect(s.error, isNull);
      expect(s.status, SessionStatus.connected);
      expect(prompts.hostKeyRequests, hasLength(1), reason: 'first connect');
      expect(prompts.secretRequests, isEmpty, reason: 'saved password used');

      await runEcho(s);

      // Resizing the terminal must reach the remote pty.
      s.terminal.resize(132, 40);
      s.terminal.textInput(
        r'echo cols-$(tput cols)'
        '\r',
      );
      await waitForText(s, 'cols-132');
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'server stats come back over a side channel',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts());
      await s.connect();
      expect(s.connectedAt, isNotNull);

      final out = await s.runCommand(serverStatsCommand);
      expect(out, isNotNull);
      final stats = ServerStats.parse(out!);
      // ignore: avoid_print
      print(
        'hostname=${stats.hostname} os=${stats.os} kernel=${stats.kernel} '
        'uptime=${stats.uptime} load=${stats.load} cpus=${stats.cpuCount} '
        'mem=${stats.memUsed}/${stats.memTotal} disk=${stats.diskUsed}/${stats.diskTotal}',
      );
      expect(stats.hostname, isNotEmpty);
      expect(stats.os, isNotEmpty);
      expect(stats.memTotal, greaterThan(0));
      expect(stats.diskTotal, greaterThan(0));
      expect(stats.cpuCount, greaterThan(0));

      // Two samples give a CPU usage figure.
      await Future<void>.delayed(const Duration(seconds: 1));
      final again = ServerStats.parse(
        (await s.runCommand(serverStatsCommand))!,
      );
      expect(
        again.cpuTimes!.usageSince(stats.cpuTimes!),
        inInclusiveRange(0, 1),
      );

      // Nothing leaked into the interactive terminal.
      expect(s.terminal.buffer.getText(), isNot(contains('@@hostname')));
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'second connect trusts the stored host key without asking',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));

      final first = FakePrompts();
      final s1 = sessionFor(host, first);
      await s1.connect();
      s1.dispose();

      final second = FakePrompts();
      final s2 = sessionFor(host, second);
      await s2.connect();
      expect(s2.status, SessionStatus.connected);
      expect(second.hostKeyRequests, isEmpty);
      s2.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'unsaved password is asked for at connect time',
    () async {
      final host = hostWith(AuthMethod.password);
      final prompts = FakePrompts(secret: _password);
      final s = sessionFor(host, prompts);

      await s.connect();
      expect(s.status, SessionStatus.connected);
      expect(prompts.secretRequests, hasLength(1), reason: 'asked once only');
      await runEcho(s);
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'wrong password fails with an auth error',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(
        host.id,
        const HostSecrets(password: 'definitely-wrong-password'),
      );
      final s = sessionFor(host, FakePrompts());

      await s.connect();
      expect(s.status, SessionStatus.failed);
      expect(s.error, contains('认证失败'));
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'rejecting the host key aborts the connection',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts(trustHostKey: false));

      await s.connect();
      expect(s.status, SessionStatus.failed);
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'private key login opens a working shell',
    () async {
      final host = hostWith(AuthMethod.key);
      await repo.writeSecrets(
        host.id,
        HostSecrets(
          privateKey: File(_keyFile!).readAsStringSync(),
          passphrase: _env['UESSH_TEST_KEY_PASSPHRASE'],
        ),
      );
      final s = sessionFor(host, FakePrompts());

      await s.connect();
      expect(s.error, isNull);
      expect(s.status, SessionStatus.connected);
      await runEcho(s);
      s.dispose();
    },
    skip: (_host == null || _user == null || _keyFile == null)
        ? 'set UESSH_TEST_HOST / USER / KEY_FILE to run'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
