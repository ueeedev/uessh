import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import 'host.dart';
import 'host_repository.dart';
import '../../l10n/l10n.dart';

final hostRepositoryProvider = Provider<HostRepository>(
  (ref) => HostRepository(
    dataDir: ref.watch(dataDirProvider),
    secrets: ref.watch(secretStoreProvider),
  ),
);

class HostsNotifier extends AsyncNotifier<HostsData> {
  HostRepository get _repo => ref.read(hostRepositoryProvider);

  HostsData get _data => state.value ?? const HostsData();

  @override
  Future<HostsData> build() => _repo.load();

  Future<void> _commit(HostsData next) async {
    await _repo.save(next);
    state = AsyncData(next);
  }

  /// Creates or updates [host]. If [newGroupName] is given, that group is
  /// created (or an existing one with the same name reused) and the host
  /// is put in it.
  Future<void> save(
    Host host,
    HostSecrets secrets, {
    String? newGroupName,
  }) async {
    var data = _data;
    if (newGroupName != null) {
      final (next, group) = _withGroup(data, newGroupName);
      data = next;
      host = host.copyWith(groupId: group.id);
    }

    final hosts = [...data.hosts];
    final i = hosts.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      hosts[i] = host;
    } else {
      hosts.add(host);
    }
    await _repo.writeSecrets(host.id, secrets);
    await _commit(data.copyWith(hosts: hosts));
  }

  Future<void> remove(String hostId) async {
    final hosts = [..._data.hosts]..removeWhere((h) => h.id == hostId);
    await _commit(_data.copyWith(hosts: hosts));
    await _repo.deleteSecrets(hostId);
  }

  /// Returns the group named [name], creating it if needed.
  Future<HostGroup> addGroup(String name) async {
    final (next, group) = _withGroup(_data, name);
    if (!identical(next, _data)) await _commit(next);
    return group;
  }

  /// Throws [ArgumentError] if another group already has [name].
  Future<void> renameGroup(String groupId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError(currentL10n.groupNameEmptyError);
    final existing = _data.groupByName(trimmed);
    if (existing != null && existing.id != groupId) {
      throw ArgumentError(currentL10n.groupNameExistsError(trimmed));
    }
    await _commit(
      _data.copyWith(
        groups: [
          for (final g in _data.groups) g.id == groupId ? g.rename(trimmed) : g,
        ],
      ),
    );
  }

  /// Deletes the group; its hosts become ungrouped (they are not deleted).
  Future<void> deleteGroup(String groupId) => _commit(
    HostsData(
      groups: [..._data.groups]..removeWhere((g) => g.id == groupId),
      hosts: [
        for (final h in _data.hosts)
          h.groupId == groupId ? h.copyWith(groupId: null) : h,
      ],
    ),
  );

  static (HostsData, HostGroup) _withGroup(HostsData data, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError(currentL10n.groupNameEmptyError);
    final existing = data.groupByName(trimmed);
    if (existing != null) return (data, existing);
    final group = HostGroup(id: generateId(), name: trimmed);
    return (data.copyWith(groups: [...data.groups, group]), group);
  }
}

final hostsProvider = AsyncNotifierProvider<HostsNotifier, HostsData>(
  HostsNotifier.new,
);
