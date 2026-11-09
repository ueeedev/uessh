// Runs in the real app build (native plugins included):
//   flutter test integration_test/local_terminal_test.dart -d macos
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/server_stats.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import '../test/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a local shell runs commands and ends on exit', (tester) async {
    await tester.runAsync(() async {
      final env = TestEnv();
      final s = LocalTerminalSession(
        host: localHost(),
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      );
      await s.connect();
      expect(s.status, SessionStatus.connected, reason: s.error);

      Future<void> waitFor(bool Function() done, String what) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!done()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('$what. Screen:\n${s.terminal.buffer.getText()}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      s.terminal.textInput(
        Platform.isWindows
            ? r'echo ("uessh-" + (40+2) + "-ok")'
                  '\r'
            : r'echo uessh-$((40+2))-ok'
                  '\r',
      );
      await waitFor(
        () => s.terminal.buffer.getText().contains('uessh-42-ok'),
        'command output never showed',
      );
      // Not the sandbox's home: the real one.
      if (Platform.isMacOS) {
        s.terminal.textInput('echo "home=\$HOME"\r');
        await waitFor(
          () => s.terminal.buffer.getText().contains(
            'home=${Platform.environment['HOME']}',
          ),
          'HOME was not passed',
        );
        expect(Platform.environment['HOME'], isNot(contains('Containers')));
      }
      if (!Platform.isWindows) {
        // The file browser follows the shell's folder.
        final tmp = Directory.systemTemp
            .createTempSync('uessh it')
            .resolveSymbolicLinksSync();
        s.sendInput(s.cdCommand(tmp));
        String? cwd;
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (cwd != tmp && DateTime.now().isBefore(deadline)) {
          cwd = await s.shellCwd();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(cwd, tmp);
        // AI commands run on this computer, in that folder, with the
        // login shell's PATH.
        final r = await s.exec('pwd; command -v ls');
        expect(r.exitCode, 0, reason: r.stderr);
        expect(r.stdout, startsWith(tmp));
        final fs = await s.remoteFs();
        File('$tmp/x.txt').writeAsStringSync('x');
        expect((await fs.list(tmp)).map((e) => e.name), contains('x.txt'));
        Directory(tmp).deleteSync(recursive: true);
      }
      // Stop ends the command.
      final cancel = Completer<void>();
      final started = DateTime.now();
      final slow = s.exec(
        Platform.isWindows ? 'Start-Sleep 30' : 'sleep 30',
        cancel: cancel.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      cancel.complete();
      await slow;
      expect(DateTime.now().difference(started).inSeconds, lessThan(10));

      // Info panel numbers for this computer.
      final out = await s.runCommand(s.statsCommand);
      expect(out, isNotNull);
      final stats = ServerStats.parse(out!);
      expect(stats.memTotal, greaterThan(0));
      expect(stats.cpuPercent, isNotNull);
      expect(stats.diskTotal, greaterThan(0));
      expect(stats.uptime!.inDays, lessThan(3650));

      s.terminal.textInput('exit\r');
      await waitFor(() => s.status != SessionStatus.connected, 'no exit');
      expect(s.status, SessionStatus.closed);
      expect(s.terminal.buffer.getText(), contains('[本地终端已退出]'));
      s.dispose();
      env.dispose();
    });
  });
}
