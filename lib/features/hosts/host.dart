import 'dart:math';

enum AuthMethod { password, key }

/// What the host card shows on its left.
enum HostIconKind {
  /// First letter of the name.
  letter,

  /// One of `hostIconChoices`.
  icon,

  /// Flag of the country the host's IP is in (looked up with ipwho.is).
  flag,
}

/// A host's card icon: the kind, plus a symbol and color where they apply.
class HostIcon {
  const HostIcon({this.kind = HostIconKind.letter, this.symbol, this.color});

  static const letter = HostIcon();

  final HostIconKind kind;

  /// Key in `hostIconChoices`, for [HostIconKind.icon].
  final String? symbol;

  /// ARGB seed color for the letter / icon; null follows the app accent.
  final int? color;

  bool get isDefault => this == letter;

  HostIcon copyWith({HostIconKind? kind, String? symbol, Object? color = _k}) =>
      HostIcon(
        kind: kind ?? this.kind,
        symbol: symbol ?? this.symbol,
        color: identical(color, _k) ? this.color : color as int?,
      );

  static const _k = Object();

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (symbol != null) 'symbol': symbol,
    if (color != null) 'color': color,
  };

  factory HostIcon.fromJson(Object? json) {
    if (json is! Map) return letter;
    return HostIcon(
      kind:
          HostIconKind.values.asNameMap()[json['kind']] ?? HostIconKind.letter,
      symbol: json['symbol'] as String?,
      color: (json['color'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HostIcon &&
      other.kind == kind &&
      other.symbol == symbol &&
      other.color == color;

  @override
  int get hashCode => Object.hash(kind, symbol, color);
}

/// Short random id for hosts and groups.
String generateId() {
  final rand = Random.secure().nextInt(1 << 32).toRadixString(36);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$rand';
}

/// A saved server. Secrets are not part of this object; they live in the
/// [SecretStore] under keys derived from [id] (see [HostSecrets]).
class Host {
  const Host({
    required this.id,
    required this.label,
    required this.address,
    required this.port,
    required this.username,
    required this.authMethod,
    this.groupId,
    this.keyId,
    this.icon = HostIcon.letter,
  });

  final String id;
  final String label;
  final String address;
  final int port;
  final String username;
  final AuthMethod authMethod;

  /// The [HostGroup] this host belongs to; null means ungrouped.
  final String? groupId;

  /// A saved key (Keys page) to log in with. Null with [AuthMethod.key]
  /// means the host has its own pasted key.
  final String? keyId;

  /// What the card shows on its left.
  final HostIcon icon;

  String get displayName => label.isNotEmpty ? label : address;

  String get target =>
      port == 22 ? '$username@$address' : '$username@$address:$port';

  static String newId() => generateId();

  static const _keep = Object();

  /// Pass `groupId: null` to clear the group; omit it to keep it.
  Host copyWith({
    String? label,
    String? address,
    int? port,
    String? username,
    AuthMethod? authMethod,
    Object? groupId = _keep,
    Object? keyId = _keep,
    HostIcon? icon,
  }) => Host(
    id: id,
    label: label ?? this.label,
    address: address ?? this.address,
    port: port ?? this.port,
    username: username ?? this.username,
    authMethod: authMethod ?? this.authMethod,
    groupId: identical(groupId, _keep) ? this.groupId : groupId as String?,
    keyId: identical(keyId, _keep) ? this.keyId : keyId as String?,
    icon: icon ?? this.icon,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'port': port,
    'username': username,
    'authMethod': authMethod.name,
    if (groupId != null) 'groupId': groupId,
    if (keyId != null) 'keyId': keyId,
    if (!icon.isDefault) 'icon': icon.toJson(),
  };

  factory Host.fromJson(Map<String, Object?> json) => Host(
    id: json['id'] as String,
    label: (json['label'] as String?) ?? '',
    address: json['address'] as String,
    port: (json['port'] as num?)?.toInt() ?? 22,
    username: json['username'] as String,
    authMethod:
        AuthMethod.values.asNameMap()[json['authMethod']] ??
        AuthMethod.password,
    groupId: json['groupId'] as String?,
    keyId: json['keyId'] as String?,
    icon: HostIcon.fromJson(json['icon']),
  );
}

/// A named folder for hosts. The name is user-defined and unique
/// (case-insensitive).
class HostGroup {
  const HostGroup({required this.id, required this.name});

  final String id;
  final String name;

  HostGroup rename(String name) => HostGroup(id: id, name: name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory HostGroup.fromJson(Map<String, Object?> json) =>
      HostGroup(id: json['id'] as String, name: json['name'] as String);
}

/// Everything in hosts.json.
class HostsData {
  const HostsData({this.groups = const [], this.hosts = const []});

  /// In display order.
  final List<HostGroup> groups;
  final List<Host> hosts;

  HostGroup? groupById(String? id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  HostGroup? groupByName(String name) {
    final key = name.trim().toLowerCase();
    for (final g in groups) {
      if (g.name.toLowerCase() == key) return g;
    }
    return null;
  }

  HostsData copyWith({List<HostGroup>? groups, List<Host>? hosts}) =>
      HostsData(groups: groups ?? this.groups, hosts: hosts ?? this.hosts);
}

class HostSecrets {
  const HostSecrets({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;
}
