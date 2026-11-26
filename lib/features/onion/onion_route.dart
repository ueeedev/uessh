import 'dart:io';

import '../../core/json_file.dart';
import '../hosts/host.dart';

/// A saved multi-hop SSH chain ("Onion Connection"): connects through
/// [jumpHostIds] in order (`A -> B -> ...`) to reach [targetHostId] (`C`),
/// so the destination only sees a connection coming from the last jump node.
class OnionRoute {
  const OnionRoute({
    required this.id,
    this.name = '',
    this.jumpHostIds = const [],
    required this.targetHostId,
    this.note,
    this.createdAt,
  });

  final String id;

  /// Optional friendly name; falls back to the hop route summary when empty.
  final String name;

  /// Intermediate jump hosts in hop order (at least one for an onion chain).
  final List<String> jumpHostIds;

  /// Final destination host whose shell is controlled.
  final String targetHostId;

  final String? note;
  final DateTime? createdAt;

  /// Ordered list of all host IDs from entry jump node to final target.
  List<String> get allHostIds => [...jumpHostIds, targetHostId];

  int get hopCount => jumpHostIds.length + 1;

  /// Resolves every hop ID against [hostById]; returns null if any host is
  /// missing or deleted, or if there is no intermediate jump node.
  ({List<Host> jumps, Host target})? resolve(Map<String, Host> hostById) {
    if (jumpHostIds.isEmpty) return null;
    final target = hostById[targetHostId];
    if (target == null) return null;
    final jumps = <Host>[];
    for (final id in jumpHostIds) {
      final h = hostById[id];
      if (h == null) return null;
      jumps.add(h);
    }
    return (jumps: jumps, target: target);
  }

  /// Display title: user-chosen [name], or `A → B → C` built from [hostById].
  String displayTitle(Map<String, Host> hostById, {String missingLabel = '?'}) {
    if (name.trim().isNotEmpty) return name.trim();
    return routeSummary(hostById, missingLabel: missingLabel);
  }

  String routeSummary(
    Map<String, Host> hostById, {
    String missingLabel = '?',
  }) =>
      [for (final id in allHostIds) hostById[id]?.displayName ?? missingLabel]
          .join(' → ');

  /// Equivalent OpenSSH `ssh -J` command for quick verification or CLI copy.
  String sshCommandPreview(Map<String, Host> hostById) {
    String hopSpec(Host? h) {
      if (h == null) return '?';
      return h.port == 22
          ? '${h.username}@${h.address}'
          : '${h.username}@${h.address}:${h.port}';
    }

    final target = hostById[targetHostId];
    final jumps = [for (final id in jumpHostIds) hopSpec(hostById[id])];
    final targetPort = (target != null && target.port != 22)
        ? ' -p ${target.port}'
        : '';
    final targetAddr = target == null
        ? '?'
        : '${target.username}@${target.address}';
    if (jumps.isEmpty) return 'ssh$targetPort $targetAddr';
    return 'ssh -J ${jumps.join(',')}$targetPort $targetAddr';
  }

  OnionRoute copyWith({
    String? name,
    List<String>? jumpHostIds,
    String? targetHostId,
    Object? note = _keep,
    DateTime? createdAt,
  }) => OnionRoute(
    id: id,
    name: name ?? this.name,
    jumpHostIds: jumpHostIds ?? this.jumpHostIds,
    targetHostId: targetHostId ?? this.targetHostId,
    note: identical(note, _keep) ? this.note : note as String?,
    createdAt: createdAt ?? this.createdAt,
  );

  static const _keep = Object();

  static String newId() => generateId();

  Map<String, Object?> toJson() => {
    'id': id,
    if (name.trim().isNotEmpty) 'name': name.trim(),
    'jumpHostIds': jumpHostIds,
    'targetHostId': targetHostId,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory OnionRoute.fromJson(Map<String, Object?> json) => OnionRoute(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    jumpHostIds: [
      for (final e in (json['jumpHostIds'] as List? ?? const []))
        if (e is String && e.isNotEmpty) e,
    ],
    targetHostId: json['targetHostId'] as String,
    note: json['note'] as String?,
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );
}

/// Persists saved onion connection cards in `<dataDir>/onion_routes.json`.
class OnionRouteRepository {
  OnionRouteRepository({required Directory dataDir})
    : _file = JsonFile(File('${dataDir.path}/onion_routes.json'));

  final JsonFile _file;

  Future<List<OnionRoute>> load() async {
    final data = await _file.read();
    if (data is! Map) return const [];
    final list = (data['routes'] as List?) ?? const [];
    return [
      for (final e in list)
        if (e is Map) OnionRoute.fromJson(e.cast<String, Object?>()),
    ];
  }

  Future<void> save(List<OnionRoute> routes) => _file.write({
    'version': 1,
    'routes': [for (final r in routes) r.toJson()],
  });
}
