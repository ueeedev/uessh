import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/info_panel.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';
import 'package:uessh/l10n/l10n.dart';
import 'package:uessh/theme/app_theme.dart';

import 'test_helpers.dart';

const _sample = '''
@@hostname
web-01
@@os
Ubuntu 24.04 LTS
@@kernel
6.8.0
@@uptime
86400
@@nproc
4
@@cpupct
25.0
@@load
0.50 0.25 0.10
@@mem
MemTotal: 8388608 kB
MemAvailable: 6291456 kB
@@disks
/dev/vda1 104857600 41943040 62914560 40% /
/dev/vdb1 209715200 52428800 157286400 25% /mnt/data files
@@processes
100 root 0.0 8192 sshd
200 deploy 12.5 65536 worker service
@@end
''';

class _SnapshotSession extends TerminalSession {
  _SnapshotSession(TestEnv env, {String name = 'test-box'})
    : super(
        host: Host(
          id: name,
          label: name,
          address: '127.0.0.1',
          port: 22,
          username: 'root',
          authMethod: AuthMethod.password,
        ),
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      ) {
    status = SessionStatus.connected;
  }

  String? sample = _sample;
  Future<String?> Function()? onRead;
  int reads = 0;

  @override
  Future<String?> runCommand(
    String command, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    reads++;
    return onRead?.call() ?? Future.value(sample);
  }

  void changeStatus(SessionStatus next) {
    status = next;
    notifyListeners();
  }
}

void main() {
  late TestEnv env;
  late _SnapshotSession session;

  setUp(() {
    env = TestEnv();
    session = _SnapshotSession(env);
  });
  tearDown(() {
    session.dispose();
    env.dispose();
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    _SnapshotSession? current,
    double width = 300,
    double height = 650,
    Locale locale = const Locale('zh'),
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: MaterialApp(
          theme: AppTheme.build(brightness, null),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: TerminalInfoPanel(
                  session: current ?? session,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> selectTab(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('four Material 3 tabs show their respective information', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(
      Theme.of(tester.element(find.byType(TerminalInfoPanel))).useMaterial3,
      isTrue,
    );
    for (final title in ['基础信息', '性能分析', '磁盘分析', '任务进程']) {
      expect(find.widgetWithText(Tab, title), findsOneWidget);
    }
    expect(find.text('web-01'), findsOneWidget);
    expect(find.textContaining('Ubuntu 24.04 LTS'), findsOneWidget);
    for (final label in ['主机名', '系统', '内核']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final label in ['连接', '名称', '地址', '认证', '状态', '运行时间', 'CPU']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('资源'), findsNothing);

    await selectTab(tester, '性能分析');
    expect(find.text('25.0%'), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('内存'), findsOneWidget);
    for (final label in ['总计', '已用', '可用', '负载', '1 分钟', '5 分钟', '15 分钟']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('8.0 GB'), findsNothing);
    expect(find.text('0.50'), findsNothing);
    final cpu = tester.getRect(find.byKey(const ValueKey('cpu-usage-circle')));
    final memory = tester.getRect(
      find.byKey(const ValueKey('memory-usage-circle')),
    );
    expect(cpu.top, memory.top);
    expect(cpu.width, memory.width);
    expect(cpu.right, lessThan(memory.left));
    for (final key in ['cpu-usage-circle', 'memory-usage-circle']) {
      final circle = find.byKey(ValueKey(key));
      expect(
        find.descendant(of: circle, matching: find.byType(Card)),
        findsNothing,
      );
      final indicator = find.descendant(
        of: circle,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(tester.getSize(indicator), const Size(80, 80));
    }
    for (final indicator in tester.widgetList<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    )) {
      expect(indicator.value, 0.25);
    }
    expect(find.text('test-box'), findsNothing);

    await selectTab(tester, '磁盘分析');
    expect(find.text('/mnt/data files'), findsOneWidget);
    expect(find.text('200 GB'), findsOneWidget);
    expect(find.text('150 GB'), findsOneWidget);

    await selectTab(tester, '任务进程');
    expect(find.text('worker service'), findsOneWidget);
    expect(find.text('PID 200 · deploy'), findsOneWidget);
    expect(find.text('CPU 12.5%'), findsOneWidget);
    expect(find.text('内存 64.0 MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('performance keeps two circles when a metric is unavailable', (
    tester,
  ) async {
    session.sample = '@@cpupct\n0\n@@end';
    await pumpPanel(tester);
    await selectTab(tester, '性能分析');
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.text('0.0%'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester
          .widgetList<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .every((indicator) => indicator.value != null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('CPU circle changes from calculating to a sampled percentage', (
    tester,
  ) async {
    session.sample = _sample.replaceAll(
      '@@cpupct\n25.0',
      '@@stat\ncpu 100 0 0 800 0 0 0 0',
    );
    await pumpPanel(tester);
    await tester.ensureVisible(find.text('性能分析'));
    await tester.tap(find.text('性能分析'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('计算中…'), findsOneWidget);
    final cpu = find.descendant(
      of: find.byKey(const ValueKey('cpu-usage-circle')),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(tester.widget<CircularProgressIndicator>(cpu).value, isNull);
    session.sample = session.sample!.replaceAll(
      'cpu 100 0 0 800 0 0 0 0',
      'cpu 130 0 0 870 0 0 0 0',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('30.0%'), findsOneWidget);
    expect(find.text('计算中…'), findsNothing);
    expect(
      tester.widget<CircularProgressIndicator>(cpu).value,
      closeTo(0.3, 1e-9),
    );
  });

  for (final (platform, system, kernelName) in [
    ('windows', 'Microsoft Windows 11 Pro', 'Windows'),
    ('macos', 'macOS 27.0', 'Darwin'),
    ('linux', '银河麒麟 V10', 'Linux'),
  ]) {
    testWidgets('$platform icon follows the target system name', (
      tester,
    ) async {
      session.sample = _sample
          .replaceAll('Ubuntu 24.04 LTS', system)
          .replaceAll('@@kernel', '@@platform\n$kernelName\n@@kernel');
      await pumpPanel(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('system-icon-$platform')), findsOneWidget);
      final text = tester.widget<Text>(find.textContaining(system));
      final span = text.textSpan! as TextSpan;
      expect(span.text, system);
      expect(span.children!.single, isA<WidgetSpan>());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unknown systems keep their name without another system icon', (
    tester,
  ) async {
    session.sample = _sample
        .replaceAll('Ubuntu 24.04 LTS', 'FreeBSD 14.2')
        .replaceAll('@@kernel', '@@platform\nFreeBSD\n@@kernel');
    await pumpPanel(tester);
    expect(find.text('FreeBSD 14.2'), findsOneWidget);
    for (final platform in ['windows', 'macos', 'linux']) {
      expect(find.byKey(ValueKey('system-icon-$platform')), findsNothing);
    }
  });

  testWidgets('failed samples can be retried manually', (tester) async {
    session.sample = null;
    await pumpPanel(tester);
    expect(find.text('无法获取系统信息'), findsOneWidget);
    session.sample = _sample;
    await tester.tap(find.byTooltip('刷新信息'));
    await tester.pumpAndSettle();
    expect(find.text('web-01'), findsOneWidget);
    expect(session.reads, 2);
  });

  testWidgets('refresh failures keep the last sample with a notice', (
    tester,
  ) async {
    await pumpPanel(tester);
    session.sample = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('web-01'), findsOneWidget);
    expect(find.text('刷新失败，正在显示上次采集的信息'), findsOneWidget);

    session.changeStatus(SessionStatus.closed);
    await tester.pumpAndSettle();
    expect(find.text('web-01'), findsNothing);
    expect(find.text('连接后显示服务器的系统信息'), findsOneWidget);
    final reads = session.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(session.reads, reads);
  });

  testWidgets('late results from the previous session are ignored', (
    tester,
  ) async {
    final pending = Completer<String?>();
    session.onRead = () => pending.future;
    await pumpPanel(tester);
    final other = _SnapshotSession(env, name: 'other-box')
      ..sample = _sample.replaceAll('web-01', 'other-system');
    addTearDown(other.dispose);
    await pumpPanel(tester, current: other);
    expect(find.text('other-system'), findsOneWidget);
    pending.complete(_sample);
    await tester.pumpAndSettle();
    expect(find.text('other-system'), findsOneWidget);
    expect(find.text('web-01'), findsNothing);
  });

  testWidgets('reconnecting discards old requests and starts a new sample', (
    tester,
  ) async {
    final pending = Completer<String?>();
    session.onRead = () => pending.future;
    await pumpPanel(tester);
    session.changeStatus(SessionStatus.closed);
    await tester.pump();
    session.onRead = null;
    session.sample = _sample.replaceAll('web-01', 'after-reconnect');
    session.changeStatus(SessionStatus.connected);
    await tester.pumpAndSettle();
    pending.complete(_sample);
    await tester.pumpAndSettle();
    expect(find.text('after-reconnect'), findsOneWidget);
    expect(find.text('web-01'), findsNothing);
  });

  testWidgets('polling never overlaps an in-flight request', (tester) async {
    final pending = Completer<String?>();
    session.onRead = () => pending.future;
    await pumpPanel(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(session.reads, 1);
    pending.complete(_sample);
    await tester.pumpAndSettle();
    session.onRead = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(session.reads, 2);
  });

  for (final brightness in Brightness.values) {
    testWidgets('narrow English panel with larger text in ${brightness.name}', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        width: 240,
        height: 300,
        locale: const Locale('en'),
        brightness: brightness,
        textScale: 1.3,
      );
      for (final title in ['Overview', 'Performance', 'Disks', 'Processes']) {
        await selectTab(tester, title);
        expect(tester.takeException(), isNull);
        if (title == 'Performance') {
          final cpu = tester.getRect(
            find.byKey(const ValueKey('cpu-usage-circle')),
          );
          final memory = tester.getRect(
            find.byKey(const ValueKey('memory-usage-circle')),
          );
          expect(cpu.top, memory.top);
          expect(cpu.right, lessThan(memory.left));
        }
      }
    });
  }
}
