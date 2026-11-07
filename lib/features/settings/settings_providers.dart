import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import 'app_settings.dart';

/// Settings read from disk before the app starts (see main()).
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(dataDir: ref.watch(dataDirProvider)),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// Applies the change right away and saves it in the background.
  void update(AppSettings Function(AppSettings s) change) {
    state = change(state);
    ref
        .read(settingsStoreProvider)
        .save(state)
        .catchError((Object e) => debugPrint('Saving settings failed: $e'));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
