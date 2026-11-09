import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_providers.dart';
import 'features/security/lock_screen.dart';
import 'features/settings/app_settings.dart';
import 'features/settings/settings_providers.dart';
import 'l10n/l10n.dart';
import 'shell/home_shell.dart';
import 'widgets/window_drag_area.dart';
import 'theme/app_theme.dart';
import 'features/files/uploads.dart';
import 'widgets/toasts.dart';

class UesshApp extends ConsumerWidget {
  const UesshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final followSystemAccent = ref.watch(
      settingsProvider.select((s) => s.followSystemAccent),
    );
    final language = ref.watch(settingsProvider.select((s) => s.language));

    // DynamicColorBuilder reads the macOS / Windows accent color when available.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final accent = followSystemAccent ? lightDynamic?.primary : null;
        return MaterialApp(
          title: 'uessh',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.build(Brightness.light, accent),
          darkTheme: AppTheme.build(Brightness.dark, accent),
          locale: switch (language) {
            AppLanguage.system => null,
            AppLanguage.zh => const Locale('zh'),
            AppLanguage.en => const Locale('en'),
          },
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          localeResolutionCallback: (system, _) => resolveAppLocale(system),
          home: const HomeShell(),
          builder: (context, child) {
            // Code without a BuildContext (SSH messages) reads this.
            currentL10n = AppLocalizations.of(context);
            return WindowCaptionOverlay(
              child: VaultGate(
                // Notices and upload progress: top right, over everything.
                child: ToastLayer(
                  header: const UploadProgressCard(),
                  child: child!,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
