import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/json_file.dart';
import '../../core/app_log.dart';

/// OpenSSH-style fingerprint text: `SHA256:<base64 without padding>`.
String formatFingerprint(Uint8List sha256) =>
    'SHA256:${base64.encode(sha256).replaceAll('=', '')}';

class KnownHostEntry {
  const KnownHostEntry(this.keyType, this.fingerprint);
  final String keyType;
  final String fingerprint;
}

/// Asks the user whether to trust a host key. [previous] is set when the
/// server's key changed since the last connection.
typedef HostKeyPrompt = Future<bool> Function({
  required String hostPort,
  required KnownHostEntry offered,
  KnownHostEntry? previous,
});

/// Trust-on-first-use store, kept in `known_hosts.json`.
class KnownHostsStore {
  KnownHostsStore({required Directory dataDir})
    : _file = JsonFile(File('${dataDir.path}/known_hosts.json'));

  final JsonFile _file;

  static String hostPort(String address, int port) =>
      '${address.toLowerCase()}:$port';

  Future<Map<String, KnownHostEntry>> _load() async {
    final data = await _file.read();
    if (data is! Map) return {};
    return {
      for (final e in data.entries)
        if (e.value is Map)
          e.key as String: KnownHostEntry(
            (e.value as Map)['type'] as String,
            (e.value as Map)['fingerprint'] as String,
          ),
    };
  }

  Future<void> _save(Map<String, KnownHostEntry> entries) => _file.write({
    for (final e in entries.entries)
      e.key: {'type': e.value.keyType, 'fingerprint': e.value.fingerprint},
  });

  /// Returns true if the connection may proceed.
  Future<bool> verify({
    required String address,
    required int port,
    required String keyType,
    required Uint8List fingerprint,
    required HostKeyPrompt prompt,
  }) async {
    final key = hostPort(address, port);
    final offered = KnownHostEntry(keyType, formatFingerprint(fingerprint));
    final entries = await _load();
    final known = entries[key];

    if (known != null &&
        known.keyType == offered.keyType &&
        known.fingerprint == offered.fingerprint) {
      return true;
    }

    final trusted = await prompt(
      hostPort: key,
      offered: offered,
      previous: known,
    );
    log.info(
      'hostkey',
      '${known == null ? 'New' : 'CHANGED'} key for $key '
          '(${offered.keyType} ${offered.fingerprint}): '
          '${trusted ? 'trusted' : 'rejected'}',
    );
    if (trusted) {
      entries[key] = offered;
      await _save(entries);
    }
    return trusted;
  }
}
