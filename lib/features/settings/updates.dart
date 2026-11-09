import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/open_url.dart';
import '../../l10n/l10n.dart';
import 'settings_page.dart' show appVersionProvider;
import 'settings_providers.dart';
import '../../widgets/toasts.dart';

/// Where releases are published.
const releasesUrl = 'https://github.com/ueeedev/uessh/releases/latest';

/// The newest published release.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.url});

  /// Without the leading "v", e.g. "0.1.6".
  final String version;

  /// The release's page on GitHub.
  final String url;
}

/// Asks where the newest version is. Replaceable in tests.
abstract class UpdateApi {
  /// The latest release; throws when it can't be read.
  Future<ReleaseInfo> latest();
}

/// GitHub's latest release (drafts and pre-releases don't count).
///
/// First from the redirect of the releases/latest page, which has no
/// rate limit; the REST API (60 requests an hour per IP without login) is
/// the fallback.
class GitHubUpdateApi implements UpdateApi {
  static final _page = Uri.parse(releasesUrl);
  static final _api = Uri.parse(
    'https://api.github.com/repos/ueeedev/uessh/releases/latest',
  );

  /// "/ueeedev/uessh/releases/tag/v0.1.5" -> "v0.1.5".
  static String? tagFromUrl(String url) {
    final m = RegExp(r'/ueeedev/uessh/releases/tag/([^/?#]+)').firstMatch(url);
    return m == null ? null : Uri.decodeComponent(m.group(1)!);
  }

  static ReleaseInfo _info(String tag, String? url) => ReleaseInfo(
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    // Only GitHub pages are opened from here.
    url: url != null && url.startsWith('https://github.com/')
        ? url
        : releasesUrl,
  );

  @override
  Future<ReleaseInfo> latest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'uessh';
    try {
      try {
        return await _fromRedirect(client);
      } catch (e) {
        log.info('update', 'Release page check failed ($e); trying the API');
      }
      return await _fromApi(client);
    } finally {
      client.close(force: true);
    }
  }

  Future<ReleaseInfo> _fromRedirect(HttpClient client) async {
    final req = await client.headUrl(_page);
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    final location = res.headers.value(HttpHeaders.locationHeader);
    final tag = location == null ? null : tagFromUrl(location);
    if (!res.isRedirect || tag == null) {
      throw HttpException('no redirect to a release (${res.statusCode})');
    }
    return _info(tag, location);
  }

  Future<ReleaseInfo> _fromApi(HttpClient client) async {
    final req = await client.getUrl(_api);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw HttpException('GitHub answered ${res.statusCode}');
    }
    final data = jsonDecode(body);
    final tag = data is Map ? data['tag_name'] : null;
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('no tag_name');
    }
    final url = data['html_url'];
    return _info(tag, url is String ? url : null);
  }
}

final updateApiProvider = Provider<UpdateApi>((ref) => GitHubUpdateApi());

/// Compares "0.1.10" and "v0.2" by number (missing parts are 0; anything
/// after "-" or "+" is ignored). Negative when [a] is older.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// What a check found.
enum UpdateResult { available, upToDate, ignored, failed }

/// Looks for a newer version and, if there is one, asks the user what to
/// do. [manual]: from the "check for updates" link (also shows a version
/// the user ignored, and says when there's nothing new or it failed);
/// otherwise the check at startup, which stays quiet unless there's a new
/// version that wasn't ignored.
Future<UpdateResult> checkForUpdates(
  BuildContext context,
  WidgetRef ref, {
  required bool manual,
}) async {
  final l = context.l10n;

  final ReleaseInfo latest;
  final String current;
  try {
    current = await ref.read(appVersionProvider.future);
    latest = await ref.read(updateApiProvider).latest();
  } catch (e) {
    log.warn('update', 'Update check failed: $e');
    if (manual) showToast(l.updateCheckFailed, kind: ToastKind.error);
    return UpdateResult.failed;
  }
  if (compareVersions(latest.version, current) <= 0) {
    log.info('update', 'Up to date ($current)');
    if (manual) showToast(l.updateUpToDate(current), kind: ToastKind.success);
    return UpdateResult.upToDate;
  }
  final ignored = ref.read(settingsProvider).ignoredUpdateVersion;
  if (!manual && ignored == latest.version) {
    log.info('update', 'v${latest.version} is out; ignored by the user');
    return UpdateResult.ignored;
  }
  log.info('update', 'v${latest.version} is out (running $current)');
  if (!context.mounted) return UpdateResult.available;
  final choice = await showDialog<_UpdateChoice>(
    context: context,
    builder: (_) => UpdateDialog(current: current, latest: latest),
  );
  switch (choice) {
    case _UpdateChoice.go:
      await openInBrowser(latest.url);
    case _UpdateChoice.ignore:
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(ignoredUpdateVersion: latest.version));
    case _UpdateChoice.later || null:
      break;
  }
  return UpdateResult.available;
}

enum _UpdateChoice { later, go, ignore }

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.current, required this.latest});

  final String current;
  final ReleaseInfo latest;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const ValueKey('update-dialog'),
      icon: const Icon(Icons.system_update_alt),
      title: Text(l.updateAvailableTitle(latest.version)),
      content: Text(l.updateAvailableBody(current)),
      actions: [
        TextButton(
          key: const ValueKey('update-ignore'),
          onPressed: () => Navigator.pop(context, _UpdateChoice.ignore),
          child: Text(l.updateIgnore),
        ),
        TextButton(
          key: const ValueKey('update-later'),
          onPressed: () => Navigator.pop(context, _UpdateChoice.later),
          child: Text(l.updateLater),
        ),
        FilledButton(
          key: const ValueKey('update-go'),
          onPressed: () => Navigator.pop(context, _UpdateChoice.go),
          child: Text(l.updateGo),
        ),
      ],
    );
  }
}

/// The "check for updates" link under the version in Settings.
class CheckUpdatesLink extends ConsumerStatefulWidget {
  const CheckUpdatesLink({super.key});

  @override
  ConsumerState<CheckUpdatesLink> createState() => _CheckUpdatesLinkState();
}

class _CheckUpdatesLinkState extends ConsumerState<CheckUpdatesLink> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await checkForUpdates(context, ref, manual: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      key: const ValueKey('check-updates'),
      onPressed: _checking ? null : _check,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: theme.textTheme.bodySmall,
      ),
      child: Text(
        _checking ? context.l10n.updateChecking : context.l10n.updateCheck,
      ),
    );
  }
}

/// Checks once, a moment after start, when the setting is on.
class StartupUpdateCheck extends ConsumerStatefulWidget {
  const StartupUpdateCheck({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _StartupUpdateCheckState extends ConsumerState<StartupUpdateCheck> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (ref.read(settingsProvider).autoCheckUpdates) {
      // Not while the window is still appearing.
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) checkForUpdates(context, ref, manual: false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
