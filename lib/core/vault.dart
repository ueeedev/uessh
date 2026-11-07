import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'json_file.dart';
import 'secret_store.dart';

/// How the vault's data key is protected.
enum VaultMode {
  /// Key kept in `vault.key` in the app data directory: no prompts.
  local,

  /// Key wrapped with a master password; the user unlocks once per launch.
  password,
}

class VaultLockedException implements Exception {
  @override
  String toString() => '保险库已锁定';
}

class WrongPasswordException implements Exception {
  @override
  String toString() => '主密码不正确';
}

/// The app's own encrypted store for passwords, private keys and
/// passphrases (replaces the system keychain).
///
/// Layout in the data directory:
/// - `vault.json`: mode, KDF parameters, the wrapped data key (password
///   mode) and all entries encrypted with AES-256-GCM.
/// - `vault.key`: the raw data key (local mode only).
///
/// Entries are encrypted with a random 256-bit data key. Switching modes
/// or changing the master password only re-wraps that key; the entries
/// themselves don't need re-encrypting.
class Vault {
  Vault._(this._dir, this._mode, this._kdf, this._wrappedKey, this._entriesBox);

  /// In-memory vault that is unlocked and never touches disk (tests).
  Vault.unlockedInMemory()
    : _dir = null,
      _mode = VaultMode.local,
      _kdf = null,
      _wrappedKey = null,
      _entriesBox = null,
      _dataKey = _randomBytes(32),
      _entries = {};

  static const _version = 1;
  static final _aes = AesGcm.with256bits();
  static final _aad = utf8.encode('uessh-vault-v1');

  final Directory? _dir;
  VaultMode _mode;
  _KdfParams? _kdf;
  _Box? _wrappedKey;
  _Box? _entriesBox;

  // Present only while unlocked.
  List<int>? _dataKey;
  Map<String, String>? _entries;

  /// Argon2id strength for new passwords (lowered only by tests).
  int kdfMemoryKiB = 65536;
  int kdfIterations = 3;

  VaultMode get mode => _mode;
  bool get isUnlocked => _dataKey != null;

  JsonFile get _file => JsonFile(File('${_dir!.path}/vault.json'));
  File get _keyFile => File('${_dir!.path}/vault.key');

  /// Opens the vault in [dir], creating a new local-mode one if none
  /// exists. A local vault comes back unlocked; a password vault comes
  /// back locked. [created] tells the caller a new vault was made.
  static Future<({Vault vault, bool created})> open(Directory dir) async {
    final file = JsonFile(File('${dir.path}/vault.json'));
    final data = await file.read();
    if (data == null) {
      final vault = Vault._(dir, VaultMode.local, null, null, null)
        .._dataKey = _randomBytes(32)
        .._entries = {};
      await vault._keyFile.parent.create(recursive: true);
      await vault._writeKeyFile();
      await vault._save();
      return (vault: vault, created: true);
    }
    final json = (data as Map).cast<String, Object?>();
    if (json['version'] != _version) {
      throw FormatException('未知的保险库版本：${json['version']}');
    }
    final mode = VaultMode.values.byName(json['mode'] as String);
    final vault = Vault._(
      dir,
      mode,
      json['kdf'] == null ? null : _KdfParams.fromJson(json['kdf'] as Map),
      json['wrappedKey'] == null
          ? null
          : _Box.fromJson(json['wrappedKey'] as Map),
      _Box.fromJson(json['entries'] as Map),
    );
    if (mode == VaultMode.local) {
      final key = base64.decode((await vault._keyFile.readAsString()).trim());
      await vault._unlockWith(key);
    }
    return (vault: vault, created: false);
  }

  /// Throws [WrongPasswordException] if [password] is wrong.
  Future<void> unlock(String password) async {
    if (_mode != VaultMode.password) return;
    await _saveChain.catchError((_) {}); // entries box must be the latest
    final kek = await _kdf!.derive(password);
    final List<int> dataKey;
    try {
      dataKey = await _decrypt(_wrappedKey!, kek);
    } on SecretBoxAuthenticationError {
      throw WrongPasswordException();
    }
    await _unlockWith(dataKey);
  }

  /// Forgets the key and decrypted entries. No-op in local mode, which
  /// has nothing to unlock with.
  void lock() {
    if (_mode != VaultMode.password) return;
    _dataKey = null;
    _entries = null;
  }

  String? read(String key) {
    final entries = _entries;
    if (entries == null) throw VaultLockedException();
    return entries[key];
  }

  /// Null or empty [value] deletes the entry.
  Future<void> write(String key, String? value) async {
    final entries = _entries;
    if (entries == null) throw VaultLockedException();
    if (value == null || value.isEmpty) {
      if (entries.remove(key) == null) return;
    } else {
      if (entries[key] == value) return;
      entries[key] = value;
    }
    await _save();
  }

  /// Switches to password mode (or changes the password if already in
  /// it). Needs the vault unlocked.
  Future<void> setPassword(String password) async {
    final dataKey = _dataKey;
    if (dataKey == null) throw VaultLockedException();
    final kdf = _KdfParams(
      _randomBytes(16),
      memoryKiB: kdfMemoryKiB,
      iterations: kdfIterations,
    );
    _wrappedKey = await _encrypt(dataKey, await kdf.derive(password));
    _kdf = kdf;
    final wasLocal = _mode == VaultMode.local;
    _mode = VaultMode.password;
    await _save(); // wrapped key on disk before the plain key goes away
    if (wasLocal && _dir != null && await _keyFile.exists()) {
      await _keyFile.delete();
    }
  }

  /// Back to local mode. Asks for the current password even though the
  /// vault is unlocked, so a walked-up-to session can't drop protection.
  Future<void> removePassword(String currentPassword) async {
    if (_mode != VaultMode.password) return;
    await _checkPassword(currentPassword);
    await _writeKeyFile(); // plain key on disk before unwrapping
    _mode = VaultMode.local;
    _kdf = null;
    _wrappedKey = null;
    await _save();
  }

  Future<void> changePassword(String current, String next) async {
    await _checkPassword(current);
    await setPassword(next);
  }

  /// Forgotten password: throws away every saved secret and starts a new,
  /// empty local vault. Hosts themselves are unaffected.
  Future<void> reset() async {
    _mode = VaultMode.local;
    _kdf = null;
    _wrappedKey = null;
    _dataKey = _randomBytes(32);
    _entries = {};
    await _writeKeyFile();
    await _save();
  }

  // --- internals ---

  Future<void> _checkPassword(String password) async {
    final kek = await _kdf!.derive(password);
    try {
      await _decrypt(_wrappedKey!, kek);
    } on SecretBoxAuthenticationError {
      throw WrongPasswordException();
    }
  }

  Future<void> _unlockWith(List<int> dataKey) async {
    final plain = await _decrypt(_entriesBox!, dataKey);
    final map = (jsonDecode(utf8.decode(plain)) as Map).cast<String, String>();
    _dataKey = dataKey;
    _entries = map;
  }

  Future<void> _writeKeyFile() async {
    if (_dir == null) return;
    await _keyFile.writeAsString(base64.encode(_dataKey!), flush: true);
  }

  Future<void> _saveChain = Future.value();

  /// Saves run one at a time in call order, each from a snapshot taken
  /// when it was requested, so the file always ends with the latest state
  /// (even if the vault is locked while a save is still running).
  Future<void> _save() {
    if (_dir == null) return Future.value();
    final plain = utf8.encode(jsonEncode(_entries));
    final key = _dataKey!;
    final header = {
      'version': _version,
      'mode': _mode.name,
      if (_kdf != null) 'kdf': _kdf!.toJson(),
      if (_wrappedKey != null) 'wrappedKey': _wrappedKey!.toJson(),
    };
    final next = _saveChain.catchError((_) {}).then((_) async {
      final box = await _encrypt(plain, key);
      _entriesBox = box;
      await _file.write({...header, 'entries': box.toJson()});
    });
    _saveChain = next;
    return next;
  }

  static Future<_Box> _encrypt(List<int> plain, List<int> key) async {
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: _aes.newNonce(),
      aad: _aad,
    );
    return _Box(box.nonce, box.cipherText, box.mac.bytes);
  }

  static Future<List<int>> _decrypt(_Box box, List<int> key) => _aes.decrypt(
    SecretBox(box.cipherText, nonce: box.nonce, mac: Mac(box.mac)),
    secretKey: SecretKey(key),
    aad: _aad,
  );

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}

/// AES-GCM output, base64 in JSON.
class _Box {
  _Box(this.nonce, this.cipherText, this.mac);

  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;

  Map<String, String> toJson() => {
    'nonce': base64.encode(nonce),
    'data': base64.encode(cipherText),
    'mac': base64.encode(mac),
  };

  factory _Box.fromJson(Map json) => _Box(
    base64.decode(json['nonce'] as String),
    base64.decode(json['data'] as String),
    base64.decode(json['mac'] as String),
  );
}

/// Argon2id settings, stored with the vault so they can be raised later.
class _KdfParams {
  _KdfParams(this.salt, {this.memoryKiB = 65536, this.iterations = 3});

  final List<int> salt;
  final int memoryKiB;
  final int iterations;

  /// Runs on a background isolate so the UI stays smooth (~0.3 s).
  Future<List<int>> derive(String password) {
    final salt = this.salt, memory = memoryKiB, iterations = this.iterations;
    return Isolate.run(() async {
      final key = await Argon2id(
        parallelism: 1,
        memory: memory,
        iterations: iterations,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      return key.extractBytes();
    });
  }

  Map<String, Object?> toJson() => {
    'name': 'argon2id',
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'salt': base64.encode(salt),
  };

  factory _KdfParams.fromJson(Map json) {
    if (json['name'] != 'argon2id') {
      throw FormatException('不支持的密钥派生算法：${json['name']}');
    }
    return _KdfParams(
      base64.decode(json['salt'] as String),
      memoryKiB: json['memoryKiB'] as int,
      iterations: json['iterations'] as int,
    );
  }
}

/// [SecretStore] backed by the vault.
class VaultSecretStore implements SecretStore {
  VaultSecretStore(this.vault);

  final Vault vault;

  @override
  Future<String?> read(String key) async => vault.read(key);

  @override
  Future<void> write(String key, String? value) => vault.write(key, value);
}

/// One-time move of secrets from the system keychain into [vault].
/// Entries that can't be read (e.g. the user denies access) are skipped
/// and left in the keychain. Returns how many entries were moved.
Future<int> migrateKeychainSecrets({
  required SecretStore keychain,
  required Vault vault,
  required Iterable<String> keys,
}) async {
  var moved = 0;
  for (final key in keys) {
    try {
      final value = await keychain.read(key);
      if (value == null || value.isEmpty) continue;
      await vault.write(key, value);
      await keychain.write(key, null);
      moved++;
    } catch (_) {
      // Keep going; this one stays in the keychain.
    }
  }
  return moved;
}
