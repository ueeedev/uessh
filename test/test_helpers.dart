import 'dart:io';

import 'package:flutter/widgets.dart' show AxisDirection, Scrollable;
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uessh/core/app_providers.dart';
import 'package:uessh/features/ai/ai_client.dart';
import 'package:uessh/features/ai/ai_config.dart';
import 'package:uessh/core/secret_store.dart';
import 'package:uessh/core/vault.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_geo.dart';
import 'package:uessh/features/hosts/reachability.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/settings/settings_providers.dart';
import 'package:uessh/features/settings/updates.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

/// A fresh temp data dir + in-memory secrets for each test.
class TestEnv {
  TestEnv()
    : dataDir = Directory.systemTemp.createTempSync('uessh_test_'),
      secrets = MemorySecretStore(),
      reachability = FakeReachabilityChecker(),
      geo = FakeGeoApi(),
      ai = FakeAiClient() {
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

  /// Stands in for AI providers.
  final FakeAiClient ai;

  /// Unlocked, local mode, memory only. Tests of the lock screen replace
  /// it with a real vault (see vault_ui_test.dart).
  Vault vault = Vault.unlockedInMemory();

  AppSettings settings = const AppSettings(language: AppLanguage.zh);

  /// What the update check finds (nothing new, unless a test says so).
  FakeUpdateApi updates = FakeUpdateApi();

  List<Override> get overrides => [
    dataDirProvider.overrideWithValue(dataDir),
    secretStoreProvider.overrideWithValue(secrets),
    vaultProvider.overrideWithValue(vault),
    // Tests are written against the Chinese UI; the test machine's locale
    // is English, so pin the language.
    initialSettingsProvider.overrideWithValue(settings),
    reachabilityCheckerProvider.overrideWithValue(reachability),
    geoApiProvider.overrideWithValue(geo),
    aiClientProvider.overrideWithValue(ai),
    updateApiProvider.overrideWithValue(updates),
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

/// Replies with [reply] split into a few chunks (or the next entry of
/// [script]), and records requests.
class FakeAiClient implements AiClient {
  String reply = 'Hello **world**\n\n```bash\ndf -h\n```';

  /// Scripted replies, used in order before falling back to [reply]. An
  /// entry without [AiDone] gets one with its text and no tool calls.
  final script = <List<AiDelta>>[];
  Map<String, List<String>> models = {};
  final requests =
      <
        ({
          String provider,
          String model,
          String system,
          List<AiTurn> turns,
          List<AiTool> tools,
        })
      >[];

  @override
  Stream<AiDelta> chat({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String system,
    required List<AiTurn> turns,
    List<AiTool> tools = const [],
  }) async* {
    requests.add((
      provider: provider.id,
      model: model,
      system: system,
      turns: turns,
      tools: tools,
    ));
    if (script.isNotEmpty) {
      final deltas = script.removeAt(0);
      final text = StringBuffer();
      var done = false;
      for (final d in deltas) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (d is AiText) text.write(d.text);
        if (d is AiDone) done = true;
        yield d;
      }
      if (!done) yield AiDone(AiTurn.assistant(text.toString()));
      return;
    }
    final step = (reply.length / 3).ceil();
    for (var i = 0; i < reply.length; i += step) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      yield AiText(
        reply.substring(i, i + step > reply.length ? reply.length : i + step),
      );
    }
    yield AiDone(AiTurn.assistant(reply));
  }

  @override
  Future<List<String>> listModels(AiProvider provider, String apiKey) async =>
      models[provider.id] ??
      ['${provider.id}-model-a', '${provider.id}-model-b'];
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
  // Load the AI settings outside the fake clock first: the settings card
  // starts loading them once it's scrolled into view, and a load started
  // under the fake clock never finishes.
  final app = find.byType(UesshApp);
  if (app.evaluate().isNotEmpty) {
    final c = ProviderScope.containerOf(tester.element(app));
    await tester.runAsync(() => c.read(aiConfigProvider.future));
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    finder,
    300,
    // The page's own (vertical) list, not the tab strip at the top.
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  // Cards scrolled into view may load files first (AI settings) and
  // change height; bring the target back into view after.
  await settleIo(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// [UpdateApi] answering from memory; counts the checks.
class FakeUpdateApi implements UpdateApi {
  FakeUpdateApi({this.version = '0.0.1', this.fail = false});

  String version;
  bool fail;
  int checks = 0;

  @override
  Future<ReleaseInfo> latest() async {
    checks++;
    if (fail) throw const SocketException('offline');
    return ReleaseInfo(
      version: version,
      url: 'https://github.com/ueeedev/uessh/releases/tag/v$version',
    );
  }
}
