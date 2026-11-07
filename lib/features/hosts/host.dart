import 'dart:math';

enum AuthMethod { password, key }

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
  });

  final String id;
  final String label;
  final String address;
  final int port;
  final String username;
  final AuthMethod authMethod;

  /// The [HostGroup] this host belongs to; null means ungrouped.
  final String? groupId;

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
  }) => Host(
    id: id,
    label: label ?? this.label,
    address: address ?? this.address,
    port: port ?? this.port,
    username: username ?? this.username,
    authMethod: authMethod ?? this.authMethod,
    groupId: identical(groupId, _keep) ? this.groupId : groupId as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'port': port,
    'username': username,
    'authMethod': authMethod.name,
    if (groupId != null) 'groupId': groupId,
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
