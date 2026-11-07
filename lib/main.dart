import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_providers.dart';
import 'core/secret_store.dart';
import 'core/vault.dart';
import 'features/hosts/host_repository.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    title: 'uessh',
    size: Size(1200, 760),
    minimumSize: Size(800, 520),
    center: true,
    // macOS: no title bar; content goes to the top edge and the traffic
    // lights float over the sidebar. Windows keeps its system title bar.
    titleBarStyle: Platform.isMacOS ? TitleBarStyle.hidden : null,
    windowButtonVisibility: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final dataDir = await getApplicationSupportDirectory();
  final settings = await SettingsStore(dataDir: dataDir).load();
  final vault = await _openVault(dataDir);

  runApp(
    ProviderScope(
      overrides: [
        dataDirProvider.overrideWithValue(dataDir),
        initialSettingsProvider.overrideWithValue(settings),
        vaultProvider.overrideWithValue(vault),
      ],
      child: const UesshApp(),
    ),
  );
}

/// Opens the encrypted vault. The first time (no vault yet), secrets saved
/// by older versions in the system keychain are moved into it; macOS may
/// ask for keychain access once during that move, never again after.
Future<Vault> _openVault(Directory dataDir) async {
  final opened = await Vault.open(dataDir);
  if (opened.created) {
    final hosts = await HostRepository(
      dataDir: dataDir,
      secrets: MemorySecretStore(),
    ).load();
    await migrateKeychainSecrets(
      keychain: KeychainSecretStore(),
      vault: opened.vault,
      keys: [for (final h in hosts.hosts) ...HostRepository.secretKeys(h.id)],
    );
  }
  return opened.vault;
}
