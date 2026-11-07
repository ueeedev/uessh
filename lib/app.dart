import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_providers.dart';
import 'features/security/lock_screen.dart';
import 'features/settings/settings_providers.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';

class UesshApp extends ConsumerWidget {
  const UesshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final followSystemAccent = ref.watch(
      settingsProvider.select((s) => s.followSystemAccent),
    );

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
          home: const HomeShell(),
          builder: (context, child) => VaultGate(child: child!),
        );
      },
    );
  }
}
