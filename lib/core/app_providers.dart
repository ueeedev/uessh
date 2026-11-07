import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secret_store.dart';

/// App support directory (hosts.json, known_hosts.json). Overridden in main().
final dataDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('dataDirProvider not overridden'),
);

final secretStoreProvider = Provider<SecretStore>(
  (ref) => KeychainSecretStore(),
);

/// Lets non-widget code (SSH sessions) show dialogs.
final rootNavigatorKey = GlobalKey<NavigatorState>();
