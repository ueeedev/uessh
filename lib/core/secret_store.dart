import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where passwords, private keys and passphrases live.
abstract class SecretStore {
  Future<String?> read(String key);

  /// Writing null or an empty string deletes the entry.
  Future<void> write(String key, String? value);
}

/// macOS Keychain / Windows Credential Manager.
class KeychainSecretStore implements SecretStore {
  // The legacy macOS keychain avoids needing a provisioning profile
  // (keychain-access-groups), so the app can run on any Mac.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}

/// For tests.
class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
