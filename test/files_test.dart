import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/files/file_browser.dart';
import 'package:uessh/features/files/files_panel.dart';
import 'package:uessh/features/files/remote_fs.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/settings/settings_providers.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

RemoteEntry dir(String path) => RemoteEntry(
  name: path.split('/').last,
  path: path,
  isDir: true,
  mode: 0x1ed,
  modified: DateTime(2026, 1, 2, 3, 4),
);

RemoteEntry file(String path, {int size = 10, String? text}) => RemoteEntry(
  name: path.split('/').last,
  path: path,
  isDir: false,
  size: size,
  mode: 0x1a4,
  modified: DateTime(2026, 5, 6, 7, 8),
);

/// A small server: / > var > log, etc.
class FakeFs implements RemoteFs {
  final tree = <String, List<RemoteEntry>>{
    '/': [dir('/var'), dir('/etc'), file('/.hidden')],
    '/var': [dir('/var/log'), dir('/var/www')],
    '/var/log': [
      file('/var/log/syslog', size: 2048),
      file('/var/log/app.log', size: 5),
      dir('/var/log/nginx'),
      file('/var/log/.secret'),
    ],
    '/var/log/nginx': [file('/var/log/nginx/error.log')],
    '/var/www': [],
    '/etc': [file('/etc/hosts')],
  };
  final files = <String, String>{
    '/var/log/app.log': 'hello from app.log',
    '/etc/hosts': '127.0.0.1 localhost',
  };
  final listed = <String>[];

  @override
  Future<String> home() async => '/root';

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    listed.add(dir);
    final l = tree[dir];
    if (l == null) throw const FileSystemException('No such file');
    return l;
  }

  @override
  Future<Uint8List> read(String path, {int maxBytes = 1 << 20}) async =>
      Uint8List.fromList(utf8.encode(files[path] ?? ''));

  @override
  Future<void> download(
    String path,
    File target, {
    void Function(int)? onProgress,
  }) => target.writeAsString(files[path] ?? '');

  final uploaded = <String>[];
  final made = <String>[];

  @override
  Future<void> upload(
    File source,
    String path, {
    void Function(int)? onProgress,
  }) async {
    final text = await source.readAsString();
    uploaded.add(path);
    files[path] = text;
    onProgress?.call(text.length);
    final dir = parentPath(path);
    tree[dir] = [
      for (final e in tree[dir] ?? const <RemoteEntry>[])
        if (e.path != path) e,
      file(path, size: text.length),
    ];
  }

  @override
  Future<void> mkdir(String path) async {
    made.add(path);
    final dir = parentPath(path);
    if (!(tree[dir] ?? const []).any((e) => e.path == path)) {
      tree[dir] = [...?tree[dir], dir_(path)];
    }
    tree[path] ??= [];
  }
}

RemoteEntry dir_(String path) => dir(path);

/// A connected session whose server is [fs] and whose shell is in [cwd].
class FakeFsSession extends TerminalSession {
  FakeFsSession(Host host, TestEnv env, this.fs)
    : super(
        host: host,
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      );

  final FakeFs fs;
  String? cwd = '/var/log';
  final typed = <String>[];

  @override
  Future<void> connect({bool auto = false}) async {
    status = SessionStatus.connected;
    notifyListeners();
  }

  @override
  Future<RemoteFs> remoteFs() async => fs;

  @override
  Future<String?> shellCwd() async => cwd;

  @override
  void sendInput(String data) => typed.add(data);
}

void main() {
  group('paths and sorting', () {
    test('path helpers', () {
      expect(ancestorsOf('/var/log/nginx'), [
        '/',
        '/var',
        '/var/log',
        '/var/log/nginx',
      ]);
      expect(ancestorsOf('/'), ['/']);
      expect(parentPath('/var/log'), '/var');
      expect(parentPath('/var'), '/');
      expect(joinPath('/', 'etc'), '/etc');
      expect(joinPath('/etc', 'hosts'), '/etc/hosts');
      expect(shellQuote("it's here"), "'it'\\''s here'");
    });

    test('folders first; hidden files left out; sort by size', () {
      final list = [
        file('/a/b.txt', size: 5),
        dir('/a/zdir'),
        file('/a/.x'),
        file('/a/a.bin', size: 50),
        dir('/a/Adir'),
      ];
      String names(List<RemoteEntry> l) => l.map((e) => e.name).join(',');
      expect(
        names(
          sortEntries(
            list,
            FileSort.name,
            true,
            showHidden: false,
            kindOf: (_) => '',
          ),
        ),
        'Adir,zdir,a.bin,b.txt',
      );
      expect(
        names(
          sortEntries(
            list,
            FileSort.size,
            false,
            showHidden: true,
            kindOf: (_) => '',
          ),
        ),
        'zdir,Adir,a.bin,.x,b.txt',
      );
    });

    test('kinds', () {
      expect(kindOf(dir('/x')), FileKind.folder);
      expect(kindOf(file('/a.PNG')), FileKind.image);
      expect(kindOf(file('/nginx.conf')), FileKind.code);
      expect(kindOf(file('/Dockerfile')), FileKind.text);
      expect(kindOf(file('/x.tar.gz')), FileKind.archive);
      expect(
        kindOf(
          const RemoteEntry(
            name: 'run',
            path: '/run',
            isDir: false,
            mode: 0x1ed,
          ),
        ),
        FileKind.executable,
      );
    });
  });

  group('file panel', () {
    late TestEnv env;
    late FakeFs fs;
    late FakeFsSession session;

    setUp(() {
      env = TestEnv();
      fs = FakeFs();
    });
    tearDown(() => env.dispose());

    Future<ProviderContainer> pumpApp(
      WidgetTester tester, {
      FileViewMode mode = FileViewMode.list,
    }) async {
      env.settings = AppSettings(language: AppLanguage.zh, fileViewMode: mode);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            sessionFactoryProvider.overrideWithValue(
              (host) => session = FakeFsSession(host, env, fs),
            ),
          ],
          child: const UesshApp(),
        ),
      );
      await settleIo(tester);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(UesshApp)),
      );
      c
          .read(sessionsProvider.notifier)
          .open(
            const Host(
              id: 'srv',
              label: 'srv',
              address: '10.0.0.1',
              port: 22,
              username: 'root',
              authMethod: AuthMethod.password,
            ),
          );
      await tester.pump(); // opening a session shows its tab
      await settleIo(tester);
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> openFiles(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('toggle-files')));
      await settleIo(tester);
      await tester.pumpAndSettle();
    }

    Future<void> doubleTap(WidgetTester tester, Finder f) async {
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(f);
      await settleIo(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('folder button sits below AI on the rail; opens at the '
        'terminal\'s folder, in a list', (tester) async {
      final c = await pumpApp(tester);
      final ai = tester.getCenter(
        find.byKey(const ValueKey('toggle-ai-panel')),
      );
      final files = tester.getCenter(
        find.byKey(const ValueKey('toggle-files')),
      );
      final info = tester.getCenter(
        find.byKey(const ValueKey('toggle-info-panel')),
      );
      // Down the right-hand rail: AI, files, info.
      // Info on top, then AI, then files.
      expect(info.dy < ai.dy && ai.dy < files.dy, isTrue);
      expect(ai.dx == files.dx && files.dx == info.dx, isTrue);

      expect(find.byKey(const ValueKey('files-panel')), findsNothing);
      await openFiles(tester);
      expect(find.byKey(const ValueKey('files-panel')), findsOneWidget);
      // Below the terminal.
      final panel = tester.getRect(find.byKey(const ValueKey('files-panel')));
      final card = tester.getRect(find.byKey(const ValueKey('terminal-card')));
      expect(panel.top, greaterThan(card.bottom));
      expect(c.read(settingsProvider).showFilePanel, isTrue);

      // /var/log, with the path above.
      expect(find.byKey(const ValueKey('crumb-/var')), findsOneWidget);
      expect(find.byKey(const ValueKey('crumb-/var/log')), findsOneWidget);
      expect(find.text('syslog'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('.secret'), findsNothing, reason: 'hidden');
      expect(find.text('3 项'), findsOneWidget);
      // Folders first.
      expect(
        tester.getTopLeft(find.text('nginx')).dy,
        lessThan(tester.getTopLeft(find.text('app.log')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('files-hidden')));
      await tester.pumpAndSettle();
      expect(find.text('.secret'), findsOneWidget);
    });

    testWidgets('open folders, back / forward / up, breadcrumb', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await openFiles(tester);
      FileBrowserState s() => c.read(fileBrowserProvider(session.id));

      await doubleTap(tester, find.text('nginx'));
      expect(s().path, '/var/log/nginx');
      expect(find.text('error.log'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('files-back')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(s().path, '/var/log');
      await tester.tap(find.byKey(const ValueKey('files-forward')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(s().path, '/var/log/nginx');

      await tester.tap(find.byKey(const ValueKey('files-up')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(s().path, '/var/log');
      expect(s().selected, '/var/log/nginx', reason: 'came from there');

      await tester.tap(find.byKey(const ValueKey('crumb-/')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(s().path, '/');
      expect(find.text('etc'), findsOneWidget);
    });

    testWidgets('icons, columns and gallery views', (tester) async {
      final c = await pumpApp(tester, mode: FileViewMode.icons);
      await openFiles(tester);
      expect(find.byKey(const ValueKey('files-icons')), findsOneWidget);
      expect(find.text('syslog'), findsOneWidget);

      // Columns: / , /var , /var/log side by side.
      await tester.tap(find.byKey(const ValueKey('view-columns')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).fileViewMode, FileViewMode.columns);
      for (final d in ['/', '/var', '/var/log']) {
        expect(find.byKey(ValueKey('column-$d')), findsOneWidget);
      }
      // Pick a file: its preview joins as the last column.
      await tester.tap(find.text('app.log'));
      // A single click counts once a double-click is ruled out.
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('hello from app.log'), findsOneWidget);
      // A folder in an upper column goes there.
      await tester.tap(find.text('www'));
      // A single click counts once a double-click is ruled out.
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(c.read(fileBrowserProvider(session.id)).path, '/var/www');
      expect(find.byKey(const ValueKey('column-/var/log')), findsNothing);

      // Gallery: big preview of the selected item, items in a strip.
      await tester.tap(
        find
                .byKey(const ValueKey('crumb-/etc'))
                .hitTestable()
                .evaluate()
                .isEmpty
            ? find.byKey(const ValueKey('crumb-/'))
            : find.byKey(const ValueKey('crumb-/etc')),
      );
      await settleIo(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('view-gallery')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('files-gallery')), findsOneWidget);
      await doubleTap(tester, find.text('etc').last);
      await tester.tap(find.text('hosts').last);
      // A single click counts once a double-click is ruled out.
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('127.0.0.1 localhost'), findsOneWidget);
    });

    testWidgets('follows the terminal: after a command, goes where the '
        'shell went', (tester) async {
      final c = await pumpApp(tester);
      await openFiles(tester);
      expect(c.read(fileBrowserProvider(session.id)).path, '/var/log');
      session.cwd = '/etc';
      session.onCommandEntered!(); // user pressed Enter (e.g. `cd /etc`)
      await tester.pump(const Duration(milliseconds: 800));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(c.read(fileBrowserProvider(session.id)).path, '/etc');
      expect(find.text('hosts'), findsOneWidget);

      // Turned off: stays put.
      await tester.tap(find.byKey(const ValueKey('files-follow')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      session.cwd = '/var';
      session.onCommandEntered!();
      await tester.pump(const Duration(milliseconds: 800));
      await settleIo(tester);
      expect(c.read(fileBrowserProvider(session.id)).path, '/etc');
    });

    testWidgets('right-click a folder: go there in the terminal', (
      tester,
    ) async {
      await pumpApp(tester);
      await openFiles(tester);
      await tester.tap(find.text('nginx'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('在终端中进入'));
      await tester.pumpAndSettle();
      expect(session.typed.single, " cd -- '/var/log/nginx'\r");
    });

    testWidgets('drag the handle to resize; closing hides it', (tester) async {
      final c = await pumpApp(tester);
      await openFiles(tester);
      final before = tester.getRect(find.byKey(const ValueKey('files-panel')));
      await tester.drag(
        find.byKey(const ValueKey('files-panel-handle')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(const ValueKey('files-panel')));
      expect(after.height - before.height, closeTo(100, 2));
      expect(c.read(settingsProvider).filePanelHeight, closeTo(380, 2));

      await tester.tap(find.byKey(const ValueKey('toggle-files')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('files-panel')), findsNothing);
    });

    /// Files dragged in from the computer, as desktop_drop reports them.
    Future<void> osDrag(WidgetTester tester, String method, Object args) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await tester.pump();
    }

    Future<void> dragFilesTo(WidgetTester tester, Offset at) async {
      await osDrag(tester, 'entered', [at.dx, at.dy]);
      await osDrag(tester, 'updated', [at.dx + 1, at.dy + 1]);
      await settleIo(tester);
      await tester.pump();
    }

    testWidgets('after a command in the same folder: no reload flash, '
        'new files still show up', (tester) async {
      final c = await pumpApp(tester);
      await openFiles(tester);
      var flashed = false;
      c.listen(fileBrowserProvider(session.id), (_, n) {
        if (n.current is AsyncLoading) flashed = true;
      });
      session.onCommandEntered!();
      await tester.pump(const Duration(milliseconds: 800));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(flashed, isFalse);

      fs.tree['/var/log'] = [...fs.tree['/var/log']!, file('/var/log/new.txt')];
      session.onCommandEntered!();
      await tester.pump(const Duration(milliseconds: 800));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(flashed, isFalse);
      expect(find.text('new.txt'), findsOneWidget);
    });

    testWidgets('drop a file on a folder in the browser: uploads there', (
      tester,
    ) async {
      final local = Directory.systemTemp.createTempSync('uessh_up_');
      addTearDown(() => local.deleteSync(recursive: true));
      final f = File('${local.path}/up.txt')..writeAsStringSync('data');

      await pumpApp(tester);
      await openFiles(tester);
      // Over the "nginx" folder row: that's the target.
      await dragFilesTo(tester, tester.getCenter(find.text('nginx')));
      expect(find.byKey(const ValueKey('drop-overlay')), findsOneWidget);
      expect(find.text('松开上传到 /var/log/nginx'), findsOneWidget);
      // Over empty space: the shown folder.
      final panel = tester.getRect(find.byKey(const ValueKey('files-panel')));
      await dragFilesTo(tester, Offset(panel.center.dx, panel.bottom - 20));
      expect(find.text('松开上传到 /var/log'), findsOneWidget);

      await dragFilesTo(tester, tester.getCenter(find.text('nginx')));
      await osDrag(tester, 'performOperation', [f.path]);
      await pumpUntil(tester, () => fs.uploaded.isNotEmpty);
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(fs.uploaded, ['/var/log/nginx/up.txt']);
      expect(fs.files['/var/log/nginx/up.txt'], 'data');
      expect(find.byKey(const ValueKey('drop-overlay')), findsNothing);
      expect(find.text('已上传 1 个文件到 /var/log/nginx'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // progress card goes
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('upload-progress')), findsNothing);
    });

    testWidgets('drop a folder on the SSH window: goes to the shell\'s '
        'folder, contents included', (tester) async {
      final local = Directory.systemTemp.createTempSync('uessh_up_');
      addTearDown(() => local.deleteSync(recursive: true));
      final site = Directory('${local.path}/site')..createSync();
      File('${site.path}/index.html').writeAsStringSync('<h1>hi</h1>');
      Directory('${site.path}/css').createSync();
      File('${site.path}/css/a.css').writeAsStringSync('p{}');

      await pumpApp(tester);
      session.cwd = '/var/www';
      final card = tester.getRect(find.byKey(const ValueKey('terminal-card')));
      await dragFilesTo(tester, card.center);
      expect(find.text('松开上传到 /var/www'), findsOneWidget);
      await osDrag(tester, 'performOperation', [site.path]);
      await pumpUntil(tester, () => fs.uploaded.length == 2);
      await settleIo(tester);
      expect(fs.made, containsAll(['/var/www/site', '/var/www/site/css']));
      expect(
        fs.uploaded,
        unorderedEquals([
          '/var/www/site/index.html',
          '/var/www/site/css/a.css',
        ]),
      );
      await tester.pump(const Duration(seconds: 5)); // progress card goes
      await tester.pumpAndSettle();
    });

    testWidgets('same name already there: skip or replace', (tester) async {
      final local = Directory.systemTemp.createTempSync('uessh_up_');
      addTearDown(() => local.deleteSync(recursive: true));
      final f = File('${local.path}/app.log')..writeAsStringSync('new');

      await pumpApp(tester);
      await openFiles(tester);
      final panel = tester.getRect(find.byKey(const ValueKey('files-panel')));
      final empty = Offset(panel.center.dx, panel.bottom - 20);

      await dragFilesTo(tester, empty);
      await osDrag(tester, 'performOperation', [f.path]);
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('替换已有的项目？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('overwrite-skip')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(fs.uploaded, isEmpty);

      await dragFilesTo(tester, empty);
      await osDrag(tester, 'performOperation', [f.path]);
      await settleIo(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('overwrite-replace')));
      await pumpUntil(tester, () => fs.uploaded.isNotEmpty);
      expect(fs.files['/var/log/app.log'], 'new');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('right-click: upload here (folder) / upload (empty space)', (
      tester,
    ) async {
      await pumpApp(tester);
      await openFiles(tester);
      await tester.tap(find.text('nginx'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('上传文件到这里…'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byKey(const ValueKey('files-panel')));
      await tester.tapAt(
        Offset(panel.center.dx, panel.bottom - 20),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('上传文件…'), findsWidgets);
      expect(find.byKey(const ValueKey('files-upload')), findsOneWidget);
    });
  });
}
