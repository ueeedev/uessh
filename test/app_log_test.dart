import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/core/app_log.dart';

import 'test_helpers.dart';

void main() {
  setUp(log.clear);

  test('keeps entries in order and formats them', () {
    log.info('ssh', 'Connecting to root@x');
    log.warn('ssh', 'slow');
    log.error('ssh', 'failed', StateError('boom'));
    final lines = log.export().split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], contains('INFO  [ssh] Connecting to root@x'));
    expect(lines[1], contains('WARN  [ssh] slow'));
    expect(lines[2], contains('ERROR [ssh] failed: Bad state: boom'));
  });

  test('caps the in-memory log', () {
    for (var i = 0; i < AppLog.maxEntries + 50; i++) {
      log.info('t', 'line $i');
    }
    expect(log.entries.length, AppLog.maxEntries);
    expect(log.entries.first.message, 'line 50', reason: 'oldest dropped');
  });

  test('writes to logs/uessh.log once attached', () async {
    final dir = Directory.systemTemp.createTempSync('uessh_log_');
    addTearDown(() => dir.deleteSync(recursive: true));
    log.info('app', 'before attach');
    await log.attachFile(dir);
    log.info('app', 'after attach');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final text = File('${dir.path}/logs/uessh.log').readAsStringSync();
    expect(text, contains('before attach'));
    expect(text, contains('after attach'));
  });

  testWidgets('settings opens the log viewer', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    log.info('ssh', 'Connected to root@10.0.0.1');
    log.error('ssh', 'Connection to root@10.0.0.2 failed');
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('open-log')));
    await tester.tap(find.byKey(const ValueKey('open-log')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected to root@10.0.0.1'), findsOneWidget);
    expect(find.textContaining('root@10.0.0.2 failed'), findsOneWidget);

    await tester.tap(find.text('只看警告和错误'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected to root@10.0.0.1'), findsNothing);
    expect(find.textContaining('root@10.0.0.2 failed'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('暂无日志'), findsOneWidget);
  });
}
