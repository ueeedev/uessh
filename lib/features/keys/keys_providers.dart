import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import 'ssh_key.dart';

final keyRepositoryProvider = Provider<KeyRepository>(
  (ref) => KeyRepository(
    dataDir: ref.watch(dataDirProvider),
    secrets: ref.watch(secretStoreProvider),
  ),
);

class KeysNotifier extends AsyncNotifier<List<SshKey>> {
  KeyRepository get _repo => ref.read(keyRepositoryProvider);

  @override
  Future<List<SshKey>> build() => _repo.load();

  Future<void> save(SshKey key, KeySecrets secrets) async {
    final keys = [...?state.value];
    final i = keys.indexWhere((k) => k.id == key.id);
    if (i >= 0) {
      keys[i] = key;
    } else {
      keys.add(key);
    }
    await _repo.writeSecrets(key.id, secrets);
    await _repo.save(keys);
    state = AsyncData(keys);
  }

  Future<void> remove(String keyId) async {
    final keys = [...?state.value]..removeWhere((k) => k.id == keyId);
    await _repo.save(keys);
    await _repo.deleteSecrets(keyId);
    state = AsyncData(keys);
  }
}

final keysProvider = AsyncNotifierProvider<KeysNotifier, List<SshKey>>(
  KeysNotifier.new,
);
