import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/json_file.dart';
import '../hosts/host.dart';

/// SSH port forwarding mode.
enum ForwardType {
  /// Local port forwarding (`ssh -L bindHost:bindPort:targetHost:targetPort`).
  local,

  /// Remote port forwarding (`ssh -R bindHost:bindPort:targetHost:targetPort`).
  remote,

  /// Dynamic SOCKS5 proxy (`ssh -D bindHost:bindPort`).
  dynamic;

  static ForwardType fromName(String? raw) {
    for (final t in values) {
      if (t.name == raw) return t;
    }
    return ForwardType.local;
  }
}

/// Persistent configuration for a single SSH port-forwarding rule.
class PortForwardRule {
  const PortForwardRule({
    required this.id,
    this.name = '',
    required this.type,
    required this.hostId,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.targetHost = '127.0.0.1',
    this.targetPort = 0,
    this.autoStart = false,
    this.note,
    this.createdAt,
  });

  final String id;

  /// Optional friendly name; falls back to [routeSummary] when empty.
  final String name;
  final ForwardType type;

  /// Saved SSH [Host.id] through which traffic is tunneled.
  final String hostId;

  /// Listen interface (local for [ForwardType.local]/[ForwardType.dynamic],
  /// remote for [ForwardType.remote]).
  final String bindHost;

  /// Listen port (1..65535; 0 lets the OS/server pick an ephemeral port).
  final int bindPort;

  /// Destination host (remote for [ForwardType.local], local for
  /// [ForwardType.remote]; unused for [ForwardType.dynamic]).
  final String targetHost;

  /// Destination port (1..65535; unused for [ForwardType.dynamic]).
  final int targetPort;

  /// Automatically start this tunnel when an SSH session to [hostId] connects.
  final bool autoStart;
  final String? note;
  final DateTime? createdAt;

  String get effectiveBindHost =>
      bindHost.trim().isEmpty ? '127.0.0.1' : bindHost.trim();

  String get effectiveTargetHost =>
      targetHost.trim().isEmpty ? '127.0.0.1' : targetHost.trim();

  String get displayName => name.trim().isNotEmpty ? name.trim() : routeSummary;

  /// Compact endpoint description independent of locale.
  String get routeSummary => switch (type) {
    ForwardType.local =>
      '$effectiveBindHost:$bindPort → $effectiveTargetHost:$targetPort',
    ForwardType.remote =>
      '$effectiveBindHost:$bindPort → $effectiveTargetHost:$targetPort',
    ForwardType.dynamic => 'socks5://$effectiveBindHost:$bindPort',
  };

  /// Address copied when the user clicks the copy button on the card.
  String copyableAddress({int? actualPort}) {
    final port = actualPort ?? bindPort;
    final host = effectiveBindHost == '0.0.0.0'
        ? '127.0.0.1'
        : effectiveBindHost;
    return switch (type) {
      ForwardType.dynamic => 'socks5://$host:$port',
      ForwardType.local || ForwardType.remote => '$host:$port',
    };
  }

  /// Equivalent OpenSSH CLI command so users can double-check bind vs target.
  String sshCommandPreview(Host? host) {
    final flag = switch (type) {
      ForwardType.local =>
        '-L $effectiveBindHost:$bindPort:$effectiveTargetHost:$targetPort',
      ForwardType.remote =>
        '-R $effectiveBindHost:$bindPort:$effectiveTargetHost:$targetPort',
      ForwardType.dynamic => '-D $effectiveBindHost:$bindPort',
    };
    if (host == null) return 'ssh -N $flag <host>';
    final portPart = host.port == 22 ? '' : ' -p ${host.port}';
    return 'ssh -N$portPart $flag ${host.username}@${host.address}';
  }

  PortForwardRule copyWith({
    String? name,
    ForwardType? type,
    String? hostId,
    String? bindHost,
    int? bindPort,
    String? targetHost,
    int? targetPort,
    bool? autoStart,
    Object? note = _keep,
    DateTime? createdAt,
  }) => PortForwardRule(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    hostId: hostId ?? this.hostId,
    bindHost: bindHost ?? this.bindHost,
    bindPort: bindPort ?? this.bindPort,
    targetHost: targetHost ?? this.targetHost,
    targetPort: targetPort ?? this.targetPort,
    autoStart: autoStart ?? this.autoStart,
    note: identical(note, _keep) ? this.note : note as String?,
    createdAt: createdAt ?? this.createdAt,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'hostId': hostId,
    'bindHost': bindHost,
    'bindPort': bindPort,
    'targetHost': targetHost,
    'targetPort': targetPort,
    'autoStart': autoStart,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory PortForwardRule.fromJson(Map<String, Object?> m) => PortForwardRule(
    id: m['id'] as String,
    name: (m['name'] as String?) ?? '',
    type: ForwardType.fromName(m['type'] as String?),
    hostId: m['hostId'] as String,
    bindHost: (m['bindHost'] as String?) ?? '127.0.0.1',
    bindPort: (m['bindPort'] as num?)?.toInt() ?? 0,
    targetHost: (m['targetHost'] as String?) ?? '127.0.0.1',
    targetPort: (m['targetPort'] as num?)?.toInt() ?? 0,
    autoStart: (m['autoStart'] as bool?) ?? false,
    note: m['note'] as String?,
    createdAt: m['createdAt'] is String
        ? DateTime.tryParse(m['createdAt'] as String)
        : null,
  );

  static final _rand = Random.secure();

  static String newId() {
    final bytes = List<int>.generate(12, (_) => _rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// Persists saved port-forwarding rules in `<dataDir>/forwards.json`.
class PortForwardRepository {
  PortForwardRepository({required Directory dataDir})
    : _file = JsonFile(File('${dataDir.path}/forwards.json'));

  final JsonFile _file;

  Future<List<PortForwardRule>> load() async {
    final data = await _file.read();
    if (data is! Map) return const [];
    final list = (data['forwards'] as List?) ?? const [];
    return [
      for (final e in list)
        PortForwardRule.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  Future<void> save(List<PortForwardRule> rules) => _file.write({
    'version': 1,
    'forwards': [for (final r in rules) r.toJson()],
  });
}
