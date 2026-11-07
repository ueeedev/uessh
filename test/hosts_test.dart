import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/hosts/hosts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  late HostRepository repo;

  setUp(() {
    env = TestEnv();
    repo = HostRepository(dataDir: env.dataDir, secrets: env.secrets);
  });
  tearDown(() => env.dispose());

  const host = Host(
    id: 'h1',
    label: '生产',
    address: 'example.com',
    port: 2222,
    username: 'root',
    authMethod: AuthMethod.key,
  );

  test('host survives a JSON round trip', () {
    final back = Host.fromJson(host.toJson());
    expect(back.toJson(), host.toJson());
    expect(back.target, 'root@example.com:2222');
  });

  test('target omits the default port; displayName falls back to address', () {
    final h = host.copyWith(port: 22, label: '');
    expect(h.target, 'root@example.com');
    expect(h.displayName, 'example.com');
  });

  test('rapid back-to-back saves do not collide', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++)
        repo.save(HostsData(hosts: [host.copyWith(port: 1000 + i)])),
    ]);
    expect((await repo.load()).hosts.single.port, 1019, reason: 'last wins');
  });

  test('empty data dir loads no hosts', () async {
    final data = await repo.load();
    expect(data.hosts, isEmpty);
    expect(data.groups, isEmpty);
  });

  test('saves and reloads hosts; secrets never touch hosts.json', () async {
    await repo.save(const HostsData(hosts: [host]));
    await repo.writeSecrets(
      host.id,
      const HostSecrets(privateKey: 'PRIVATE-KEY', passphrase: 'pw'),
    );

    final loaded = await repo.load();
    expect(loaded.hosts.single.toJson(), host.toJson());

    final json = File('${env.dataDir.path}/hosts.json').readAsStringSync();
    expect(json, isNot(contains('PRIVATE-KEY')));

    final s = await repo.readSecrets(host.id);
    expect(s.privateKey, 'PRIVATE-KEY');
    expect(s.passphrase, 'pw');
    expect(s.password, isNull);
  });

  test('deleteSecrets clears all stored secrets', () async {
    await repo.writeSecrets(host.id, const HostSecrets(password: 'secret'));
    await repo.deleteSecrets(host.id);
    expect(env.secrets.values, isEmpty);
  });

  group('groups', () {
    test('groups and membership survive a save/load round trip', () async {
      const g = HostGroup(id: 'g1', name: '生产');
      await repo.save(
        HostsData(
          groups: const [g],
          hosts: [host.copyWith(groupId: 'g1')],
        ),
      );
      final data = await repo.load();
      expect(data.groups.single.name, '生产');
      expect(data.hosts.single.groupId, 'g1');
    });

    test('version 1 files (no groups) still load, all ungrouped', () async {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync(
        '{"version":1,"hosts":[{"id":"a","label":"","address":"x",'
        '"port":22,"username":"u","authMethod":"password"}]}',
      );
      final data = await repo.load();
      expect(data.groups, isEmpty);
      expect(data.hosts.single.groupId, isNull);
    });

    test('a host pointing at a missing group loads as ungrouped', () async {
      await repo.save(HostsData(hosts: [host.copyWith(groupId: 'gone')]));
      expect((await repo.load()).hosts.single.groupId, isNull);
    });

    test('copyWith keeps the group unless it is set or cleared', () {
      final h = host.copyWith(groupId: 'g1');
      expect(h.copyWith(port: 2).groupId, 'g1');
      expect(h.copyWith(groupId: null).groupId, isNull);
    });
  });

  group('HostsNotifier groups', () {
    late ProviderContainer container;
    late HostsNotifier notifier;

    setUp(() async {
      container = ProviderContainer(overrides: env.overrides);
      await container.read(hostsProvider.future);
      notifier = container.read(hostsProvider.notifier);
    });
    tearDown(() => container.dispose());

    HostsData data() => container.read(hostsProvider).value!;

    test('saving with a new group name creates the group', () async {
      await notifier.save(host, const HostSecrets(), newGroupName: ' 生产 ');
      final g = data().groups.single;
      expect(g.name, '生产');
      expect(data().hosts.single.groupId, g.id);
      // Persisted too.
      expect((await repo.load()).groups.single.name, '生产');
    });

    test('a new group with an existing name (any case) reuses it', () async {
      final g = await notifier.addGroup('Web');
      await notifier.save(host, const HostSecrets(), newGroupName: 'web');
      expect(data().groups, hasLength(1));
      expect(data().hosts.single.groupId, g.id);
    });

    test('rename rejects empty and duplicate names', () async {
      final a = await notifier.addGroup('A');
      await notifier.addGroup('B');
      await notifier.renameGroup(a.id, 'C');
      expect(data().groups.map((g) => g.name), ['C', 'B']);
      expect(() => notifier.renameGroup(a.id, 'b'), throwsArgumentError);
      expect(() => notifier.renameGroup(a.id, '  '), throwsArgumentError);
    });

    test('deleting a group keeps its hosts, now ungrouped', () async {
      await notifier.save(host, const HostSecrets(), newGroupName: '生产');
      await notifier.deleteGroup(data().groups.single.id);
      expect(data().groups, isEmpty);
      expect(data().hosts.single.groupId, isNull);
    });
  });
}
