import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/json_file.dart';

/// How host reachability is checked.
enum ReachabilityMethod {
  /// ICMP echo via the system `ping` command.
  ping,

  /// TCP connect to the host's SSH port. Works when ICMP is blocked.
  sshPort,
}

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.followSystemAccent = true,
    this.checkIntervalSeconds = defaultCheckInterval,
    this.checkMethod = ReachabilityMethod.ping,
    this.autoLockMinutes = defaultAutoLock,
    this.showTerminalInfo = false,
  });

  /// Lock after this many idle minutes (master password only); 0 = never.
  static const defaultAutoLock = 15;
  static const autoLockChoices = [0, 5, 15, 30, 60];

  static const defaultCheckInterval = 30;

  /// Choices offered in settings, in seconds.
  static const checkIntervalChoices = [10, 15, 30, 60, 120, 300];

  final ThemeMode themeMode;
  final bool followSystemAccent;
  final int checkIntervalSeconds;
  final ReachabilityMethod checkMethod;
  final int autoLockMinutes;

  /// Whether the info panel beside the terminal is open.
  final bool showTerminalInfo;

  Duration get checkInterval => Duration(seconds: checkIntervalSeconds);

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? followSystemAccent,
    int? checkIntervalSeconds,
    ReachabilityMethod? checkMethod,
    int? autoLockMinutes,
    bool? showTerminalInfo,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    followSystemAccent: followSystemAccent ?? this.followSystemAccent,
    checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
    checkMethod: checkMethod ?? this.checkMethod,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    showTerminalInfo: showTerminalInfo ?? this.showTerminalInfo,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'followSystemAccent': followSystemAccent,
    'checkIntervalSeconds': checkIntervalSeconds,
    'checkMethod': checkMethod.name,
    'autoLockMinutes': autoLockMinutes,
    'showTerminalInfo': showTerminalInfo,
  };

  /// Unknown or invalid values fall back to defaults.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings();
    final interval = (json['checkIntervalSeconds'] as num?)?.toInt();
    final autoLock = (json['autoLockMinutes'] as num?)?.toInt();
    return AppSettings(
      themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? d.themeMode,
      followSystemAccent:
          json['followSystemAccent'] as bool? ?? d.followSystemAccent,
      checkIntervalSeconds: (interval != null && interval >= 5)
          ? interval
          : d.checkIntervalSeconds,
      checkMethod:
          ReachabilityMethod.values.asNameMap()[json['checkMethod']] ??
          d.checkMethod,
      autoLockMinutes: (autoLock != null && autoLock >= 0)
          ? autoLock
          : d.autoLockMinutes,
      showTerminalInfo: json['showTerminalInfo'] as bool? ?? d.showTerminalInfo,
    );
  }
}

/// `settings.json` in the app data directory.
class SettingsStore {
  SettingsStore({required Directory dataDir})
    : _file = JsonFile(File('${dataDir.path}/settings.json'));

  final JsonFile _file;

  Future<AppSettings> load() async {
    try {
      final data = await _file.read();
      if (data is Map) {
        return AppSettings.fromJson(data.cast<String, Object?>());
      }
    } on FormatException {
      // Corrupt file: start from defaults rather than failing to launch.
    }
    return const AppSettings();
  }

  Future<void> save(AppSettings s) => _file.write(s.toJson());
}
