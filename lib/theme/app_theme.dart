import 'package:flutter/material.dart';

class AppTheme {
  /// Used when the system accent color is unavailable or turned off.
  static const seed = Color(0xFF3F6FD8);

  static ThemeData build(Brightness brightness, Color? accent) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent ?? seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      visualDensity: VisualDensity.compact, // desktop pointer density
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
