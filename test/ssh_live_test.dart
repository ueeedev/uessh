// Connects to a real SSH server. Skipped unless these are set:
//   UESSH_TEST_HOST, UESSH_TEST_USER, UESSH_TEST_PASSWORD
//   UESSH_TEST_PORT (optional, default 22)
// Optional key auth: UESSH_TEST_KEY_FILE (+ UESSH_TEST_KEY_PASSPHRASE).
// Only runs harmless commands on the server (echo, ls; the reconnect test
// ends its own SSH session's process).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/server_stats.dart';
import 'package:uessh/features/files/remote_fs.dart';
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
    'broadcast: typing in one session runs in the other',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final a = sessionFor(host, FakePrompts());
      final b = sessionFor(host, FakePrompts());
      await a.connect();
      await b.connect();
      expect(b.status, SessionStatus.connected);
      a.onUserInput = b.sendInput;
      a.terminal.textInput('echo uessh-bcast-\$((40+2))\r');
      await waitForText(a, 'uessh-bcast-42');
      await waitForText(b, 'uessh-bcast-42');
      a.dispose();
      b.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'files: SFTP listing; the shell\'s folder follows cd (nested too)',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts());
      await s.connect();
      expect(s.status, SessionStatus.connected);

      final fs = await s.remoteFs();
      final root = await fs.list('/');
      expect(root.map((e) => e.name), containsAll(['etc', 'tmp', 'usr']));
      expect(root.firstWhere((e) => e.name == 'etc').isDir, isTrue);
      final home = await fs.home();
      expect(home, startsWith('/'));
      final hosts = await fs.read('/etc/hostname', maxBytes: 200);
      expect(hosts, isNotEmpty);

      // Upload into a fresh folder, read it back, clean up.
      final dir = '/tmp/uessh-up-${DateTime.now().microsecondsSinceEpoch}';
      await fs.mkdir(dir);
      await fs.mkdir(dir); // again: fine
      final local = File(
        '${Directory.systemTemp.createTempSync('uessh_live_').path}/a.txt',
      )..writeAsStringSync('uessh upload ✓\n' * 2000);
      var sent = 0;
      await fs.upload(local, '$dir/a.txt', onProgress: (n) => sent = n);
      expect(sent, local.lengthSync());
      final back = await fs.read('$dir/a.txt', maxBytes: 1 << 20);
      expect(back, local.readAsBytesSync());
      final listed = await fs.list(dir);
      expect(listed.single.name, 'a.txt');
      expect(listed.single.size, local.lengthSync());
      await s.exec('rm -rf ${shellQuote(dir)}');

      expect(await s.shellCwd(), home, reason: 'starts at home');
      s.terminal.textInput('cd /tmp\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await s.shellCwd(), '/tmp');
      // A nested shell: its folder wins.
      s.terminal.textInput('bash\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      s.terminal.textInput('cd /usr/share\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await s.shellCwd(), '/usr/share');
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'shell folder without the LC_ marker (server refuses env)',
    () async {
      TerminalSession.debugNoShellMarker = true;
      addTearDown(() => TerminalSession.debugNoShellMarker = false);
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts());
      await s.connect();
      expect(s.status, SessionStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      s.terminal.textInput('cd /tmp\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await s.shellCwd(), '/tmp');
      s.terminal.textInput('bash\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      s.terminal.textInput('cd /usr/share\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await s.shellCwd(), '/usr/share');

      // A second session on the same server: each finds its own shell.
      final s2 = sessionFor(host, FakePrompts());
      await Future<void>.delayed(const Duration(seconds: 2));
      await s2.connect();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      s2.terminal.textInput('cd /etc\r');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await s2.shellCwd(), '/etc');
      expect(await s.shellCwd(), '/usr/share');
      s.dispose();
      s2.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'exec: output, stderr and exit code, outside the terminal',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts());
      await s.connect();
      expect(s.status, SessionStatus.connected);

      final ok = await s.exec('uname -s; echo err-line 1>&2');
      expect(ok.stdout.trim(), 'Linux');
      expect(ok.stderr.trim(), 'err-line');
      expect(ok.exitCode, 0);

      final fail = await s.exec('ls /definitely-not-here-uessh');
      expect(fail.exitCode, isNot(0));
      expect(fail.stderr, isNotEmpty);

      final slow = await s.exec('sleep 5', timeout: const Duration(seconds: 1));
      expect(slow.timedOut, isTrue);

      final shown = await s.execShown('echo shown-\$((20+1)); echo e>&2');
      expect(shown.exitCode, 0);
      final screen = s.terminal.buffer.getText();
      expect(screen, contains('── AI ──'));
      expect(screen, contains(r'$ echo shown-'));
      expect(screen, contains('shown-21'));
      expect(screen, contains('✓ exit 0'));

      // Stop: the command ends on the server too.
      await s.exec('rm -f /tmp/uessh-stop-x');
      final cancel = Completer<void>();
      Timer(const Duration(milliseconds: 800), cancel.complete);
      final watch = Stopwatch()..start();
      await s.exec('sleep 3; touch /tmp/uessh-stop-x', cancel: cancel.future);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      await Future<void>.delayed(const Duration(seconds: 4));
      final left = await s.exec('ls /tmp/uessh-stop-x 2>/dev/null');
      expect(left.stdout.trim(), isEmpty, reason: 'killed before touch');

      final big = await s.exec('seq 1 100000', maxBytes: 1000);
      expect(big.truncated, isTrue);
      expect(big.stdout.length, lessThanOrEqualTo(1000));
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );

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

  test(
    'reconnect: a dropped connection comes back; exit does not reconnect',
    () async {
      final host = hostWith(AuthMethod.password);
      await repo.writeSecrets(host.id, HostSecrets(password: _password));
      final s = sessionFor(host, FakePrompts());
      s.reconnectPolicy = () =>
          (enabled: true, attempts: 3, delay: const Duration(seconds: 1));
      await s.connect();
      expect(s.status, SessionStatus.connected);

      // The shell's parent is this session's sshd process: killing it drops
      // the connection without an exit status, like a network failure.
      s.terminal.textInput('kill -9 \$PPID\r');
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (s.reconnectAttempt == 0 && s.status == SessionStatus.connected) {
        if (DateTime.now().isAfter(deadline)) fail('connection never dropped');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(s.reconnectAttempt, 1);
      await waitForText(s, '1/3');
      while (s.status != SessionStatus.connected) {
        if (DateTime.now().isAfter(deadline)) fail('did not reconnect');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(s.reconnectAttempt, 0);
      await runEcho(s);

      // `exit` ends the shell with a status: no reconnect.
      s.terminal.textInput('exit\r');
      while (s.status == SessionStatus.connected) {
        if (DateTime.now().isAfter(deadline.add(const Duration(seconds: 10)))) {
          fail('exit did not close');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(s.status, SessionStatus.closed);
      expect(s.reconnectPending, isFalse);
      s.dispose();
    },
    skip: skipPassword,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
