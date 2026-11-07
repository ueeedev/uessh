import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/vault.dart';

class VaultState {
  const VaultState({required this.mode, required this.unlocked});

  final VaultMode mode;
  final bool unlocked;

  bool get hasPassword => mode == VaultMode.password;
  bool get locked => !unlocked;
}

/// UI-facing wrapper around the [Vault]: every change goes through here so
/// widgets rebuild when the vault locks, unlocks or changes mode.
class VaultController extends Notifier<VaultState> {
  Vault get _vault => ref.read(vaultProvider);

  @override
  VaultState build() => _read();

  VaultState _read() =>
      VaultState(mode: _vault.mode, unlocked: _vault.isUnlocked);

  void _sync() => state = _read();

  /// Throws [WrongPasswordException].
  Future<void> unlock(String password) async {
    await _vault.unlock(password);
    _sync();
  }

  void lock() {
    _vault.lock();
    _sync();
  }

  Future<void> setPassword(String password) async {
    await _vault.setPassword(password);
    _sync();
  }

  Future<void> changePassword(String current, String next) async {
    await _vault.changePassword(current, next);
    _sync();
  }

  Future<void> removePassword(String current) async {
    await _vault.removePassword(current);
    _sync();
  }

  /// Forgotten password: wipes saved secrets, keeps hosts.
  Future<void> reset() async {
    await _vault.reset();
    _sync();
  }
}

final vaultControllerProvider = NotifierProvider<VaultController, VaultState>(
  VaultController.new,
);
