import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/ai/ai_chat.dart' show systemPrompt;
import 'package:uessh/features/terminal/server_stats.dart';
import 'package:uessh/features/files/remote_fs.dart';
import 'package:uessh/features/files/local_fs.dart';
import 'package:uessh/core/sandbox_migration.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

/// Never connects: this test is about the button and the tab. (A plain
/// session would dial localhost:22, where CI machines run an SSH server.)
class _IdleSession extends TerminalSession {
  _IdleSession({
    required super.host,
    required super.repository,
    required super.knownHosts,
    required super.prompts,
  });

  @override
  Future<void> connect({bool auto = false}) async {}
}

void main() {
  group('sandbox data migration', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('uessh-mig'));
    tearDown(() => root.deleteSync(recursive: true));

    Directory container() => Directory(
      '${root.path}/Library/Containers/dev.ueee.uessh/Data/Library/'
      'Application Support/dev.ueee.uessh',
    );
    Directory appSupport() =>
        Directory('${root.path}/Library/Application Support/dev.ueee.uessh');

    test('copies the container once; leaves the container alone', () async {
      final c = container()..createSync(recursive: true);
      File('${c.path}/hosts.json').writeAsStringSync('{"hosts":[]}');
      File('${c.path}/vault.key').writeAsStringSync('k');
      Directory('${c.path}/logs').createSync();
      File('${c.path}/logs/uessh.log').writeAsStringSync('old');
      // Today's log is already written before the copy runs.
      final dest = appSupport();
      Directory('${dest.path}/logs').createSync(recursive: true);
      File('${dest.path}/logs/uessh.log').writeAsStringSync('new');

      expect(await migrateSandboxData(dest, home: root.path), isTrue);
      expect(
        File('${dest.path}/hosts.json').readAsStringSync(),
        '{"hosts":[]}',
      );
      expect(File('${dest.path}/vault.key').existsSync(), isTrue);
      expect(File('${dest.path}/logs/uessh.log').readAsStringSync(), 'new');
      expect(File('${c.path}/hosts.json').existsSync(), isTrue);

      // Second start: there's data now, nothing is copied over it.
      File('${dest.path}/hosts.json').writeAsStringSync('changed');
      expect(await migrateSandboxData(dest, home: root.path), isFalse);
      expect(File('${dest.path}/hosts.json').readAsStringSync(), 'changed');
    });

    test('no container: nothing to do', () async {
      expect(await migrateSandboxData(appSupport(), home: root.path), isFalse);
    });
  });

  testWidgets('Local terminal button sits above Settings and opens a tab', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <Host>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          sessionFactoryProvider.overrideWithValue((host) {
            opened.add(host);
            return _IdleSession(
              host: host,
              repository: HostRepository(
                dataDir: env.dataDir,
                secrets: env.secrets,
              ),
              knownHosts: KnownHostsStore(dataDir: env.dataDir),
              prompts: FakePrompts(),
            );
          }),
        ],
        child: const UesshApp(),
      ),
    );
    await settleIo(tester);

    final button = find.byKey(const ValueKey('open-local-terminal'));
    expect(
      find.descendant(of: button, matching: find.text('本地终端')),
      findsOneWidget,
    );
    final settings = tester.getRect(find.text('设置').last);
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(settings.top));

    await tester.tap(button);
    await tester.pump();
    expect(opened.single.id, localHostId);
    expect(opened.single.label, '本地终端');
    await settleIo(tester);
  });

  test('when the shell can\'t start, the tab says why', () async {
    // flutter test runs without the plugin's native library: starting
    // fails, which must end in a readable error, not a crash. The real
    // shell is tested in integration_test/local_terminal_test.dart.
    final env = TestEnv();
    addTearDown(env.dispose);
    final s = LocalTerminalSession(
      host: localHost(),
      repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
      knownHosts: KnownHostsStore(dataDir: env.dataDir),
      prompts: FakePrompts(),
    );
    await s.connect();
    expect(s.status, SessionStatus.failed);
    expect(s.error, startsWith('无法启动本地终端'));
    expect(s.reconnectPending, isFalse);
    s.dispose();
  });

  group('LocalFs', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('uessh-fs'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lists, reads, copies in and out, makes folders', () async {
      final fs = LocalFs(windows: false);
      File('${dir.path}/a.txt').writeAsStringSync('hello');
      Directory('${dir.path}/sub').createSync();
      Link('${dir.path}/to-sub').createSync('${dir.path}/sub');

      final entries = {for (final e in await fs.list(dir.path)) e.name: e};
      expect(entries.keys, containsAll(['a.txt', 'sub', 'to-sub']));
      expect(entries['a.txt']!.size, 5);
      expect(entries['a.txt']!.path, '${dir.path}/a.txt');
      expect(entries['sub']!.isDir, isTrue);
      expect(entries['to-sub']!.isDir, isTrue);
      expect(entries['to-sub']!.isLink, isTrue);

      expect(String.fromCharCodes(await fs.read('${dir.path}/a.txt')), 'hello');
      expect(
        String.fromCharCodes(await fs.read('${dir.path}/a.txt', maxBytes: 2)),
        'he',
      );

      final sent = <int>[];
      await fs.upload(
        File('${dir.path}/a.txt'),
        '${dir.path}/sub/b.txt',
        onProgress: sent.add,
      );
      expect(File('${dir.path}/sub/b.txt').readAsStringSync(), 'hello');
      expect(sent.last, 5);
      await fs.download('${dir.path}/sub/b.txt', File('${dir.path}/c.txt'));
      expect(File('${dir.path}/c.txt').readAsStringSync(), 'hello');

      await fs.mkdir('${dir.path}/new');
      await fs.mkdir('${dir.path}/new'); // already there: fine
      expect(Directory('${dir.path}/new').existsSync(), isTrue);
    });

    test('Windows paths: drives are top folders', () {
      final fs = LocalFs(windows: true);
      expect(fs.fromNative(r'C:\Users\me'), '/C:/Users/me');
      expect(fs.fromNative(r'C:\'), '/C:/');
      expect(fs.toNative('/C:/Users/me'), 'C:/Users/me');
      expect(fs.toNative('/C:'), 'C:/');
      // The browser's own helpers work on these paths.
      expect(parentPath('/C:/Users'), '/C:');
      expect(parentPath('/C:'), '/');
      expect(ancestorsOf('/C:/Users'), ['/', '/C:', '/C:/Users']);
    });
  });

  test('macOS / Windows info: CPU as a percentage', () {
    final s = ServerStats.parse('''
@@hostname
My Mac
@@os
macOS 15.1
@@uptime
780004
@@load
 3.38 5.10 5.33
@@nproc
10
@@cpupct
21.9
@@mem
MemTotal: 16777216 kB
MemAvailable: 4488816 kB
@@disk
/dev/disk3s5   482746452 269786836 175813572    61%    /System/Volumes/Data
@@end
''');
    expect(s.hostname, 'My Mac');
    expect(s.cpuPercent, 21.9);
    expect(s.cpuTimes, isNull);
    expect(s.hasResources, isTrue);
    expect(s.memTotal, 16777216 * 1024);
    expect(s.memUsed, (16777216 - 4488816) * 1024);
    expect(s.diskUsed, 269786836 * 1024);
    expect(s.uptime, const Duration(seconds: 780004));
    expect(s.load, [3.38, 5.10, 5.33]);
  });

  test('the AI is told it works on this computer, not a server', () {
    final env = TestEnv();
    addTearDown(env.dispose);
    final local = LocalTerminalSession(
      host: localHost(),
      repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
      knownHosts: KnownHostsStore(dataDir: env.dataDir),
      prompts: FakePrompts(),
    );
    addTearDown(local.dispose);
    final prompt = systemPrompt(local, tools: true);
    expect(prompt, contains('local terminal on their own computer'));
    expect(prompt, contains(Platform.operatingSystem));
    expect(prompt, isNot(contains('connected to localhost')));
    expect(local.statsCommand, isNot(serverStatsCommand));
    expect(local.cdCommand('/tmp/a b'), " cd -- '/tmp/a b'\r");
  });
}
