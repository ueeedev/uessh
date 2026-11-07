import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/core/app_providers.dart';
import 'package:uessh/core/secret_store.dart';
import 'package:uessh/core/vault.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/reachability.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

/// A fresh temp data dir + in-memory secrets for each test.
class TestEnv {
  TestEnv()
    : dataDir = Directory.systemTemp.createTempSync('uessh_test_'),
      secrets = MemorySecretStore(),
      reachability = FakeReachabilityChecker();

  final Directory dataDir;
  final MemorySecretStore secrets;
  final FakeReachabilityChecker reachability;

  /// Unlocked, local mode, memory only. Tests of the lock screen replace
  /// it with a real vault (see vault_ui_test.dart).
  Vault vault = Vault.unlockedInMemory();

  List<Override> get overrides => [
    dataDirProvider.overrideWithValue(dataDir),
    secretStoreProvider.overrideWithValue(secrets),
    vaultProvider.overrideWithValue(vault),
    reachabilityCheckerProvider.overrideWithValue(reachability),
  ];

  void dispose() {
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  }
}

/// Answers every prompt automatically and records what was asked.
class FakePrompts implements SessionPrompts {
  FakePrompts({this.trustHostKey = true, this.secret});

  bool trustHostKey;
  String? secret;
  final hostKeyRequests = <({String hostPort, KnownHostEntry? previous})>[];
  final secretRequests = <String>[];

  @override
  Future<bool> confirmHostKey({
    required String hostPort,
    required KnownHostEntry offered,
    KnownHostEntry? previous,
  }) async {
    hostKeyRequests.add((hostPort: hostPort, previous: previous));
    return trustHostKey;
  }

  @override
  Future<String?> askSecret({
    required String title,
    required String message,
  }) async {
    secretRequests.add(title);
    return secret;
  }
}

/// Answers instantly: addresses in [up] are reachable, others are not.
class FakeReachabilityChecker implements ReachabilityChecker {
  final up = <String, Duration>{};
  final calls = <({String address, ReachabilityMethod method})>[];

  int callsFor(String address) =>
      calls.where((c) => c.address == address).length;

  @override
  Future<Duration?> check(Host host, ReachabilityMethod method) async {
    calls.add((address: host.address, method: method));
    return up[host.address];
  }
}

/// File I/O completes on the real event loop, but widget tests run on a
/// fake clock. Each await in a disk operation needs a real-time turn
/// followed by a pump, so alternate the two a few times.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Pumps until [done] is true, letting real async work (file I/O,
/// isolates) progress between frames. Fails after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('pumpUntil timed out');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    // Advance the fake clock too, so route transitions can finish.
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}
