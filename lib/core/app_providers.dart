import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secret_store.dart';
import 'vault.dart';

/// App support directory (hosts.json, known_hosts.json). Overridden in main().
final dataDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('dataDirProvider not overridden'),
);

/// The app's encrypted secret store. Opened in main() and overridden.
final vaultProvider = Provider<Vault>(
  (ref) => throw UnimplementedError('vaultProvider not overridden'),
);

final secretStoreProvider = Provider<SecretStore>(
  (ref) => VaultSecretStore(ref.watch(vaultProvider)),
);

/// Lets non-widget code (SSH sessions) show dialogs.
final rootNavigatorKey = GlobalKey<NavigatorState>();
