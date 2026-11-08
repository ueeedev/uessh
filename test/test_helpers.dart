import 'dart:io';

import 'package:flutter/widgets.dart' show ListView, Scrollable;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uessh/core/app_providers.dart';
import 'package:uessh/core/secret_store.dart';
import 'package:uessh/core/vault.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_geo.dart';
import 'package:uessh/features/hosts/reachability.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/settings/settings_providers.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

/// A fresh temp data dir + in-memory secrets for each test.
class TestEnv {
  TestEnv()
    : dataDir = Directory.systemTemp.createTempSync('uessh_test_'),
      secrets = MemorySecretStore(),
      reachability = FakeReachabilityChecker(),
      geo = FakeGeoApi() {
    PackageInfo.setMockInitialValues(
      appName: 'uessh',
      packageName: 'dev.ueee.uessh',
      version: '0.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
  }

  final Directory dataDir;
  final MemorySecretStore secrets;
  final FakeReachabilityChecker reachability;

  /// Stands in for ipwho.is; tests never go online.
  final FakeGeoApi geo;

  /// Unlocked, local mode, memory only. Tests of the lock screen replace
  /// it with a real vault (see vault_ui_test.dart).
  Vault vault = Vault.unlockedInMemory();

  AppSettings settings = const AppSettings(language: AppLanguage.zh);

  List<Override> get overrides => [
    dataDirProvider.overrideWithValue(dataDir),
    secretStoreProvider.overrideWithValue(secrets),
    vaultProvider.overrideWithValue(vault),
    // Tests are written against the Chinese UI; the test machine's locale
    // is English, so pin the language.
    initialSettingsProvider.overrideWithValue(settings),
    reachabilityCheckerProvider.overrideWithValue(reachability),
    geoApiProvider.overrideWithValue(geo),
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

/// Answers like ipwho.is from [places] (ip -> country code) and records
/// what was asked. Names in [dns] resolve to IPs; anything else must be
/// an IP already.
class FakeGeoApi implements GeoApi {
  final places = <String, String>{};
  final dns = <String, String>{};
  final lookups = <String>[];
  final downloads = <Uri>[];

  static const flagSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 3 2">'
      '<rect width="3" height="2" fill="#de2910"/></svg>';

  @override
  Future<InternetAddress?> resolve(String address) async =>
      InternetAddress.tryParse(dns[address] ?? address);

  @override
  Future<Map<String, Object?>> lookup(String ip) async {
    lookups.add(ip);
    final code = places[ip];
    if (code == null) return {'success': false, 'message': 'Not found'};
    return {
      'success': true,
      'country': 'Country $code',
      'country_code': code,
      'region': 'Region',
      'city': 'City',
      'flag': {'img': 'https://cdn.ipwhois.io/flags/${code.toLowerCase()}.svg'},
    };
  }

  @override
  Future<String> download(Uri url) async {
    downloads.add(url);
    return flagSvg;
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

/// Scrolls the page's list until [finder] is built and on screen (lists
/// build lazily, so far-down items don't exist until scrolled to).
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}
