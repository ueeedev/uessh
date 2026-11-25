import 'dart:io';

import 'app_log.dart';

/// Parsed OS system proxy settings (macOS `scutil --proxy` or Windows
/// Internet Settings registry).
class SystemProxyConfig {
  const SystemProxyConfig({
    this.httpProxy,
    this.httpsProxy,
    this.bypass = const [],
  });

  static const direct = SystemProxyConfig();

  /// `host:port` for `http://` requests (e.g. `127.0.0.1:7890`).
  final String? httpProxy;

  /// `host:port` for `https://` requests (e.g. `127.0.0.1:7890`).
  final String? httpsProxy;

  /// Host patterns that bypass the system proxy (`ExceptionsList` on macOS,
  /// `ProxyOverride` on Windows).
  final List<String> bypass;

  bool get hasProxy => httpProxy != null || httpsProxy != null;

  /// Resolves the `HttpClient.findProxy` directive for [url].
  String resolveFor(Uri url) {
    if (!hasProxy || isLoopbackHost(url.host) || shouldBypass(url.host)) {
      return 'DIRECT';
    }
    final scheme = url.scheme.toLowerCase();
    final proxy = switch (scheme) {
      'https' || 'wss' => httpsProxy,
      'http' || 'ws' => httpProxy,
      _ => null,
    };
    if (proxy == null || proxy.isEmpty) return 'DIRECT';
    // Fall back to DIRECT if the configured proxy port stops listening.
    return 'PROXY $proxy; DIRECT';
  }

  /// Whether [host] matches any entry in [bypass].
  bool shouldBypass(String host) {
    final normalized = _normalizeHost(host);
    if (normalized.isEmpty) return false;
    final ip = InternetAddress.tryParse(normalized);
    for (final raw in bypass) {
      final pattern = raw.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (pattern == '<local>') {
        if (!normalized.contains('.') || isLoopbackHost(normalized)) {
          return true;
        }
        continue;
      }
      if (pattern.contains('/')) {
        if (ip != null && _matchesIpv4Cidr(ip, pattern)) return true;
        continue;
      }
      if (pattern.contains('*')) {
        // Treat `*.example.com` as matching both subdomains and bare domain.
        if (pattern.startsWith('*.')) {
          final suffix = pattern.substring(2);
          if (normalized == suffix || normalized.endsWith('.$suffix')) {
            return true;
          }
        }
        if (_globMatches(pattern, normalized)) return true;
        continue;
      }
      if (pattern.startsWith('.')) {
        final suffix = pattern.substring(1);
        if (normalized == suffix || normalized.endsWith(pattern)) return true;
        continue;
      }
      if (normalized == pattern) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is SystemProxyConfig &&
      other.httpProxy == httpProxy &&
      other.httpsProxy == httpsProxy &&
      other.bypass.length == bypass.length &&
      Iterable<int>.generate(bypass.length)
          .every((i) => other.bypass[i] == bypass[i]);

  @override
  int get hashCode =>
      Object.hash(httpProxy, httpsProxy, Object.hashAll(bypass));
}

bool isLoopbackHost(String host) {
  final h = _normalizeHost(host);
  return h == 'localhost' || h == '::1' || h.startsWith('127.');
}

String _normalizeHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) {
    h = h.substring(1, h.length - 1);
  }
  return h;
}

String? _formatHostPort(String? host, String? portRaw) {
  final h = host?.trim() ?? '';
  final port = int.tryParse(portRaw?.trim() ?? '');
  if (h.isEmpty || port == null || port < 1 || port > 65535) return null;
  final formattedHost = h.contains(':') && !h.startsWith('[') ? '[$h]' : h;
  return '$formattedHost:$port';
}

/// Strips optional `http://` or `https://` prefix from a Windows proxy value
/// and returns `host:port` (or null for unsupported schemes like `socks=`).
String? _normalizeProxyEndpoint(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (value.contains('://')) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty || !uri.hasPort || uri.port < 1 || uri.port > 65535) {
      return null;
    }
    final h = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return '$h:${uri.port}';
  }
  if (value.endsWith('/')) value = value.substring(0, value.length - 1);
  final lastColon = value.lastIndexOf(':');
  if (lastColon <= 0) return null;
  final host = value.substring(0, lastColon);
  final port = value.substring(lastColon + 1);
  return _formatHostPort(host, port);
}

bool _globMatches(String pattern, String value) {
  final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
  return RegExp('^$escaped\$', caseSensitive: false).hasMatch(value);
}

bool _matchesIpv4Cidr(InternetAddress ip, String cidr) {
  if (ip.type != InternetAddressType.IPv4) return false;
  final parts = cidr.split('/');
  if (parts.length != 2) return false;
  final net = InternetAddress.tryParse(parts[0].trim());
  final prefix = int.tryParse(parts[1].trim());
  if (net == null ||
      net.type != InternetAddressType.IPv4 ||
      prefix == null ||
      prefix < 0 ||
      prefix > 32) {
    return false;
  }
  int toInt(InternetAddress a) {
    final b = a.rawAddress;
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return (toInt(ip) & mask) == (toInt(net) & mask);
}

/// Parses `scutil --proxy` output on macOS.
SystemProxyConfig parseMacOsScutilProxy(String output) {
  final values = <String, String>{};
  final exceptions = <String>[];
  var inExceptions = false;

  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (inExceptions) {
      if (line == '}') {
        inExceptions = false;
        continue;
      }
      final m = RegExp(r'^\d+\s*:\s*(.+)$').firstMatch(line);
      if (m != null) {
        final entry = m.group(1)!.trim();
        if (entry.isNotEmpty) exceptions.add(entry);
      }
      continue;
    }
    if (line.startsWith('ExceptionsList') && line.contains('{')) {
      inExceptions = true;
      continue;
    }
    final kv = RegExp(r'^([A-Za-z0-9_]+)\s*:\s*(.+)$').firstMatch(line);
    if (kv != null) {
      values[kv.group(1)!] = kv.group(2)!.trim();
    }
  }

  final httpProxy = values['HTTPEnable'] == '1'
      ? _formatHostPort(values['HTTPProxy'], values['HTTPPort'])
      : null;
  final httpsProxy = values['HTTPSEnable'] == '1'
      ? _formatHostPort(values['HTTPSProxy'], values['HTTPSPort'])
      : null;

  return SystemProxyConfig(
    httpProxy: httpProxy,
    httpsProxy: httpsProxy,
    bypass: exceptions,
  );
}

/// Parses `reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"`
/// output on Windows.
SystemProxyConfig parseWindowsRegProxy(String output) {
  String? proxyEnable;
  String? proxyServer;
  String? proxyOverride;

  for (final rawLine in output.split('\n')) {
    final m = RegExp(r'^\s*([A-Za-z0-9_]+)\s+REG_[A-Z_]+\s+(.*)$')
        .firstMatch(rawLine);
    if (m == null) continue;
    final key = m.group(1)!.toLowerCase();
    final val = m.group(2)!.trim();
    switch (key) {
      case 'proxyenable':
        proxyEnable = val;
      case 'proxyserver':
        proxyServer = val;
      case 'proxyoverride':
        proxyOverride = val;
    }
  }

  final enabled =
      proxyEnable != null &&
      (proxyEnable == '1' ||
          proxyEnable.toLowerCase() == '0x1' ||
          int.tryParse(proxyEnable) == 1);
  if (!enabled || proxyServer == null || proxyServer.isEmpty) {
    return SystemProxyConfig.direct;
  }

  String? httpProxy;
  String? httpsProxy;
  if (proxyServer.contains('=')) {
    for (final part in proxyServer.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final scheme = part.substring(0, eq).trim().toLowerCase();
      final endpoint = _normalizeProxyEndpoint(part.substring(eq + 1));
      if (endpoint == null) continue;
      if (scheme == 'http') httpProxy = endpoint;
      if (scheme == 'https') httpsProxy = endpoint;
    }
  } else {
    final endpoint = _normalizeProxyEndpoint(proxyServer);
    httpProxy = endpoint;
    httpsProxy = endpoint;
  }

  final bypass = <String>[
    if (proxyOverride != null)
      for (final item in proxyOverride.split(RegExp('[;,]')))
        if (item.trim().isNotEmpty) item.trim(),
  ];

  return SystemProxyConfig(
    httpProxy: httpProxy,
    httpsProxy: httpsProxy,
    bypass: bypass,
  );
}

/// Queries the current OS proxy settings synchronously (fast local IPC/registry
/// lookup, ~7ms on macOS). Returns [SystemProxyConfig.direct] on error or
/// unsupported platforms.
SystemProxyConfig readOsSystemProxySync() {
  try {
    if (Platform.isMacOS) {
      final r = Process.runSync('/usr/sbin/scutil', const ['--proxy']);
      if (r.exitCode == 0 && r.stdout is String) {
        return parseMacOsScutilProxy(r.stdout as String);
      }
    } else if (Platform.isWindows) {
      final r = Process.runSync('reg', const [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      ]);
      if (r.exitCode == 0 && r.stdout is String) {
        return parseWindowsRegProxy(r.stdout as String);
      }
    }
  } catch (e) {
    log.warn('net', 'Failed to read system proxy settings: $e');
  }
  return SystemProxyConfig.direct;
}

/// Resolves proxies for `dart:io` [HttpClient]: honors explicit environment
/// variables (`HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`) first, and falls back
/// to OS system proxy settings (essential for GUI-launched desktop apps that
/// do not inherit shell proxy variables).
class SystemProxyResolver {
  SystemProxyResolver({
    this.ttl = const Duration(seconds: 5),
    SystemProxyConfig Function()? loadSystemProxy,
    Map<String, String> Function()? readEnvironment,
    DateTime Function()? now,
  }) : _loadSystemProxy = loadSystemProxy ?? readOsSystemProxySync,
       _readEnvironment = readEnvironment ?? (() => Platform.environment),
       _now = now ?? DateTime.now;

  final Duration ttl;
  final SystemProxyConfig Function() _loadSystemProxy;
  final Map<String, String> Function() _readEnvironment;
  final DateTime Function() _now;

  SystemProxyConfig? _cached;
  DateTime? _cachedAt;

  /// Pre-warms or refreshes the cached OS proxy settings.
  SystemProxyConfig refresh() {
    final config = _loadSystemProxy();
    _cached = config;
    _cachedAt = _now();
    return config;
  }

  SystemProxyConfig _current() {
    final cached = _cached;
    final at = _cachedAt;
    if (cached != null && at != null && _now().difference(at) < ttl) {
      return cached;
    }
    return refresh();
  }

  /// Suitable for [HttpClient.findProxy].
  String findProxy(Uri url) {
    if (isLoopbackHost(url.host)) return 'DIRECT';

    final env = _readEnvironment();
    if (_hasExplicitEnvProxy(env)) {
      return HttpClient.findProxyFromEnvironment(url, environment: env);
    }

    return _current().resolveFor(url);
  }

  static bool _hasExplicitEnvProxy(Map<String, String> env) {
    for (final key in const [
      'http_proxy',
      'HTTP_PROXY',
      'https_proxy',
      'HTTPS_PROXY',
    ]) {
      final v = env[key];
      if (v != null && v.trim().isNotEmpty) return true;
    }
    return false;
  }
}

/// Global [HttpOverrides] that wires [SystemProxyResolver] into every
/// [HttpClient] created by the app (AI assistant, update checks, host geo).
class SystemProxyHttpOverrides extends HttpOverrides {
  SystemProxyHttpOverrides({SystemProxyResolver? resolver})
    : resolver = resolver ?? SystemProxyResolver();

  final SystemProxyResolver resolver;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = resolver.findProxy;
    return client;
  }
}
