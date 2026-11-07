import 'dart:io';

import '../../core/json_file.dart';
import '../../core/secret_store.dart';
import 'host.dart';

/// Hosts and groups in `hosts.json`; secrets in the [SecretStore].
class HostRepository {
  HostRepository({required Directory dataDir, required this.secrets})
    : _file = JsonFile(File('${dataDir.path}/hosts.json'));

  final JsonFile _file;
  final SecretStore secrets;

  /// Reads version 1 (hosts only) and version 2 (hosts + groups) files.
  Future<HostsData> load() async {
    final data = await _file.read();
    if (data is! Map) return const HostsData();

    final groups = [
      if (data['groups'] is List)
        for (final g in data['groups'] as List)
          HostGroup.fromJson((g as Map).cast<String, Object?>()),
    ];
    final groupIds = {for (final g in groups) g.id};
    final hosts = [
      if (data['hosts'] is List)
        for (final item in data['hosts'] as List)
          Host.fromJson((item as Map).cast<String, Object?>()),
    ];
    return HostsData(
      groups: groups,
      hosts: [
        // A host pointing at a missing group is shown as ungrouped.
        for (final h in hosts)
          (h.groupId == null || groupIds.contains(h.groupId))
              ? h
              : h.copyWith(groupId: null),
      ],
    );
  }

  Future<void> save(HostsData data) => _file.write({
    'version': 2,
    'groups': [for (final g in data.groups) g.toJson()],
    'hosts': [for (final h in data.hosts) h.toJson()],
  });

  Future<HostSecrets> readSecrets(String hostId) async => HostSecrets(
    password: await secrets.read(_key(hostId, 'password')),
    privateKey: await secrets.read(_key(hostId, 'privateKey')),
    passphrase: await secrets.read(_key(hostId, 'passphrase')),
  );

  Future<void> writeSecrets(String hostId, HostSecrets s) async {
    await secrets.write(_key(hostId, 'password'), s.password);
    await secrets.write(_key(hostId, 'privateKey'), s.privateKey);
    await secrets.write(_key(hostId, 'passphrase'), s.passphrase);
  }

  Future<void> deleteSecrets(String hostId) =>
      writeSecrets(hostId, const HostSecrets());

  static String _key(String hostId, String field) =>
      'uessh.host.$hostId.$field';
}
