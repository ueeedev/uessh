import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';

import '../../core/json_file.dart';
import '../../core/secret_store.dart';
import '../../features/hosts/host.dart' show generateId;
import '../terminal/known_hosts.dart' show formatFingerprint;
import '../../l10n/l10n.dart';

/// A saved private key. The key text and passphrase live in the vault;
/// this holds only what is safe to show.
class SshKey {
  const SshKey({
    required this.id,
    required this.name,
    this.keyType,
    this.fingerprint,
    this.publicKey,
  });

  final String id;
  final String name;

  /// e.g. `ssh-ed25519`; null for an encrypted key saved without its
  /// passphrase (we can't look inside).
  final String? keyType;

  /// `SHA256:...` of the public key.
  final String? fingerprint;

  /// One `authorized_keys` line: `ssh-ed25519 AAAA... name`.
  final String? publicKey;

  static String newId() => generateId();

  SshKey copyWith({String? name, KeyInfo? info}) => SshKey(
    id: id,
    name: name ?? this.name,
    keyType: info != null ? info.keyType : keyType,
    fingerprint: info != null ? info.fingerprint : fingerprint,
    publicKey: info != null ? info.publicKey : publicKey,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'keyType': ?keyType,
    'fingerprint': ?fingerprint,
    'publicKey': ?publicKey,
  };

  factory SshKey.fromJson(Map<String, Object?> json) => SshKey(
    id: json['id'] as String,
    name: json['name'] as String,
    keyType: json['keyType'] as String?,
    fingerprint: json['fingerprint'] as String?,
    publicKey: json['publicKey'] as String?,
  );
}

class KeySecrets {
  const KeySecrets({this.privateKey, this.passphrase});
  final String? privateKey;
  final String? passphrase;
}

/// What we could learn from a private key.
class KeyInfo {
  const KeyInfo({this.keyType, this.fingerprint, this.publicKey});
  final String? keyType;
  final String? fingerprint;
  final String? publicKey;
}

class InvalidKeyException implements Exception {
  const InvalidKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses [pem] (with [passphrase] if it's encrypted). An encrypted key
/// without a passphrase is accepted but can't be inspected: the user is
/// asked for the passphrase when connecting. Throws [InvalidKeyException].
Future<KeyInfo> inspectPrivateKey(
  String pem,
  String? passphrase, {
  String comment = '',
}) async {
  final text = pem.trim();
  if (text.isEmpty) throw InvalidKeyException(currentL10n.keyRequired);
  final List<SSHKeyPair> pairs;
  try {
    final encrypted = SSHKeyPair.isEncryptedPem(text);
    if (encrypted && (passphrase ?? '').isEmpty) return const KeyInfo();
    pairs = SSHKeyPair.fromPem(text, encrypted ? passphrase : null);
  } on SSHKeyDecryptError {
    throw InvalidKeyException(currentL10n.keyWrongPassphrase);
  } catch (_) {
    throw InvalidKeyException(currentL10n.keyUnrecognized);
  }
  if (pairs.isEmpty) throw InvalidKeyException(currentL10n.keyEmpty);
  final pair = pairs.first;
  final blob = pair.toPublicKey().encode();
  final hash = await Sha256().hash(blob);
  final line = [
    pair.type,
    base64.encode(blob),
    if (comment.isNotEmpty) comment,
  ];
  return KeyInfo(
    keyType: pair.type,
    fingerprint: formatFingerprint(Uint8List.fromList(hash.bytes)),
    publicKey: line.join(' '),
  );
}

/// Key list in `keys.json`; key text and passphrase in the [SecretStore].
class KeyRepository {
  KeyRepository({required Directory dataDir, required this.secrets})
    : _file = JsonFile(File('${dataDir.path}/keys.json'));

  final JsonFile _file;
  final SecretStore secrets;

  Future<List<SshKey>> load() async {
    final data = await _file.read();
    if (data is! Map || data['keys'] is! List) return [];
    return [
      for (final k in data['keys'] as List)
        SshKey.fromJson((k as Map).cast<String, Object?>()),
    ];
  }

  Future<void> save(List<SshKey> keys) => _file.write({
    'version': 1,
    'keys': [for (final k in keys) k.toJson()],
  });

  Future<KeySecrets> readSecrets(String keyId) async => KeySecrets(
    privateKey: await secrets.read(_key(keyId, 'privateKey')),
    passphrase: await secrets.read(_key(keyId, 'passphrase')),
  );

  Future<void> writeSecrets(String keyId, KeySecrets s) async {
    await secrets.write(_key(keyId, 'privateKey'), s.privateKey);
    await secrets.write(_key(keyId, 'passphrase'), s.passphrase);
  }

  Future<void> deleteSecrets(String keyId) =>
      writeSecrets(keyId, const KeySecrets());

  static String _key(String keyId, String field) => 'uessh.key.$keyId.$field';
}
