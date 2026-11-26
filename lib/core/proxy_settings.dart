/// How outbound connections for a feature (AI or SSH) route through a proxy.
enum ProxyMode {
  /// Follow OS system proxy settings (or process environment variables).
  system,

  /// Connect directly without any proxy.
  direct,

  /// Connect through a manually configured HTTP or SOCKS5 proxy.
  custom,
}

/// Protocol spoken by a manually configured proxy server.
enum ProxyScheme { http, socks5 }

/// Non-secret proxy configuration stored in `settings.json`. Optional proxy
/// passwords are kept separately in the encrypted [Vault].
class ProxySettings {
  const ProxySettings({
    this.mode = ProxyMode.direct,
    this.scheme = ProxyScheme.http,
    this.host = '',
    this.port = defaultPort,
    this.username = '',
  });

  static const defaultPort = 7890;

  static const aiDefault = ProxySettings(mode: ProxyMode.system);
  static const sshDefault = ProxySettings(mode: ProxyMode.direct);

  final ProxyMode mode;
  final ProxyScheme scheme;
  final String host;
  final int port;
  final String username;

  bool get isCustomValid =>
      mode == ProxyMode.custom &&
      host.trim().isNotEmpty &&
      port >= 1 &&
      port <= 65535;

  String get formattedHostPort {
    final h = host.trim();
    if (h.isEmpty) return '';
    final bracketed = h.contains(':') && !h.startsWith('[') ? '[$h]' : h;
    return '$bracketed:$port';
  }

  String get displayEndpoint {
    final hp = formattedHostPort;
    return hp.isEmpty ? '' : '${scheme.name}://$hp';
  }

  ProxySettings copyWith({
    ProxyMode? mode,
    ProxyScheme? scheme,
    String? host,
    int? port,
    String? username,
  }) => ProxySettings(
    mode: mode ?? this.mode,
    scheme: scheme ?? this.scheme,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'scheme': scheme.name,
    if (host.trim().isNotEmpty) 'host': host.trim(),
    'port': port,
    if (username.trim().isNotEmpty) 'username': username.trim(),
  };

  factory ProxySettings.fromJson(
    Object? raw, {
    required ProxySettings fallback,
  }) {
    if (raw is! Map) return fallback;
    final mode = ProxyMode.values.asNameMap()[raw['mode']] ?? fallback.mode;
    final scheme =
        ProxyScheme.values.asNameMap()[raw['scheme']] ?? fallback.scheme;
    final host = (raw['host'] as String?)?.trim() ?? fallback.host;
    final port = ((raw['port'] as num?)?.toInt() ?? fallback.port).clamp(
      1,
      65535,
    );
    final username = (raw['username'] as String?)?.trim() ?? fallback.username;
    return ProxySettings(
      mode: mode,
      scheme: scheme,
      host: host,
      port: port,
      username: username,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProxySettings &&
      other.mode == mode &&
      other.scheme == scheme &&
      other.host == host &&
      other.port == port &&
      other.username == username;

  @override
  int get hashCode => Object.hash(mode, scheme, host, port, username);
}

/// Vault keys for optional proxy passwords (never stored in `settings.json`).
const aiProxyPasswordKey = 'uessh.proxy.ai.password';
const sshProxyPasswordKey = 'uessh.proxy.ssh.password';
