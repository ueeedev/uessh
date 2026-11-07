import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_providers.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    title: 'uessh',
    size: Size(1200, 760),
    minimumSize: Size(800, 520),
    center: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final dataDir = await getApplicationSupportDirectory();
  final settings = await SettingsStore(dataDir: dataDir).load();

  runApp(
    ProviderScope(
      overrides: [
        dataDirProvider.overrideWithValue(dataDir),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const UesshApp(),
    ),
  );
}
