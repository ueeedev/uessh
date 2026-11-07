import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Platform monospace font, with CJK fallbacks so Chinese lines up.
String get monoFontFamily =>
    defaultTargetPlatform == TargetPlatform.windows ? 'Consolas' : 'Menlo';

const monoFontFallback = [
  'Menlo',
  'Consolas',
  'SF Mono',
  'Cascadia Mono',
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans Mono CJK SC',
  'Apple Color Emoji',
  'Segoe UI Emoji',
];

TerminalStyle terminalTextStyle({double fontSize = 13}) => TerminalStyle(
  fontSize: fontSize,
  fontFamily: monoFontFamily,
  fontFamilyFallback: monoFontFallback,
);

/// Background, text, cursor and selection come from the M3 scheme so the
/// terminal sits naturally in the app; ANSI colors are tuned per brightness.
TerminalTheme terminalThemeFor(ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  final p = dark ? _darkAnsi : _lightAnsi;
  return TerminalTheme(
    background: dark ? scheme.surfaceContainerLowest : scheme.surface,
    foreground: scheme.onSurface,
    cursor: scheme.primary,
    selection: scheme.primary.withValues(alpha: 0.3),
    black: p[0],
    red: p[1],
    green: p[2],
    yellow: p[3],
    blue: p[4],
    magenta: p[5],
    cyan: p[6],
    white: p[7],
    brightBlack: p[8],
    brightRed: p[9],
    brightGreen: p[10],
    brightYellow: p[11],
    brightBlue: p[12],
    brightMagenta: p[13],
    brightCyan: p[14],
    brightWhite: p[15],
    searchHitBackground: const Color(0xFFFFDF5D),
    searchHitBackgroundCurrent: const Color(0xFFFF9632),
    searchHitForeground: const Color(0xFF000000),
  );
}

const _darkAnsi = [
  Color(0xFF3B3F45),
  Color(0xFFF2777A),
  Color(0xFF99CC99),
  Color(0xFFE6C07B),
  Color(0xFF6CB6FF),
  Color(0xFFCC99CC),
  Color(0xFF66CCCC),
  Color(0xFFD3D7DC),
  Color(0xFF6A7079),
  Color(0xFFFF8F8F),
  Color(0xFFB5E8B0),
  Color(0xFFFFD98A),
  Color(0xFF9CCBFF),
  Color(0xFFE5B5E5),
  Color(0xFF8CE6E6),
  Color(0xFFFFFFFF),
];

const _lightAnsi = [
  Color(0xFF24292F),
  Color(0xFFC62828),
  Color(0xFF2E7D32),
  Color(0xFF9A6700),
  Color(0xFF1565C0),
  Color(0xFF8E24AA),
  Color(0xFF00838F),
  Color(0xFF6E7781),
  Color(0xFF57606A),
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFB08800),
  Color(0xFF1E88E5),
  Color(0xFFAB47BC),
  Color(0xFF00ACC1),
  Color(0xFF8C959F),
];
