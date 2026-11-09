import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_providers.dart';
import 'core/app_log.dart';
import 'core/sandbox_migration.dart';
import 'core/secret_store.dart';
import 'core/vault.dart';
import 'features/hosts/host_repository.dart';
import 'shell/background_mode.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  log.captureErrors();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    title: 'uessh',
    size: Size(1200, 760),
    minimumSize: Size(800, 520),
    center: true,
    // No system title bar: content goes to the top edge. macOS traffic
    // lights float over the sidebar; on Windows the app draws its own
    // caption buttons (WindowCaptionOverlay).
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final dataDir = await getApplicationSupportDirectory();
  // The macOS app used to be sandboxed: bring over its data once.
  var migrated = false;
  final home = Platform.environment['HOME'];
  if (Platform.isMacOS && home != null) {
    try {
      migrated = await migrateSandboxData(dataDir, home: home);
    } catch (e) {
      // Logged below; the app still starts (with empty data).
      log.warn('app', 'Could not copy data from the sandbox container: $e');
    }
  }
  await log.attachFile(dataDir);
  if (migrated) log.info('app', 'Copied data from the old sandbox container');
  log.info(
    'app',
    'uessh started on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
  final settings = await SettingsStore(dataDir: dataDir).load();
  final vault = await _openVault(dataDir);

  // One container for the app and the tray/background service.
  final container = ProviderContainer(
    overrides: [
      dataDirProvider.overrideWithValue(dataDir),
      initialSettingsProvider.overrideWithValue(settings),
      vaultProvider.overrideWithValue(vault),
    ],
  );
  runApp(
    UncontrolledProviderScope(container: container, child: const UesshApp()),
  );
  await BackgroundMode(container).start();
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
    final moved = await migrateKeychainSecrets(
      keychain: KeychainSecretStore(),
      vault: opened.vault,
      keys: [for (final h in hosts.hosts) ...HostRepository.secretKeys(h.id)],
    );
    log.info('vault', 'Created vault; moved $moved secret(s) from keychain');
  }
  log.info('vault', 'Vault opened (${opened.vault.mode.name} mode)');
  return opened.vault;
}
