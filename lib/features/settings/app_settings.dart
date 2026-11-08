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

/// UI language; [system] follows the OS (Chinese if it's Chinese,
/// English otherwise).
enum AppLanguage { system, zh, en }

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.followSystemAccent = true,
    this.checkIntervalSeconds = defaultCheckInterval,
    this.checkMethod = ReachabilityMethod.ping,
    this.autoLockMinutes = defaultAutoLock,
    this.showTerminalInfo = false,
    this.infoPanelWidth = defaultInfoPanelWidth,
    this.language = AppLanguage.system,
    this.showHostOverview = true,
    this.lastConnectedHostId,
    this.lastConnectedAt,
  });

  /// Lock after this many idle minutes (master password only); 0 = never.
  static const defaultAutoLock = 15;
  static const autoLockChoices = [0, 5, 15, 30, 60];

  static const defaultCheckInterval = 30;

  /// Choices offered in settings, in seconds.
  /// Choices offered in settings, in seconds; 0 turns checking off.
  static const checkIntervalChoices = [0, 10, 15, 30, 60, 120, 300];

  final ThemeMode themeMode;
  final bool followSystemAccent;
  final int checkIntervalSeconds;
  final ReachabilityMethod checkMethod;
  final int autoLockMinutes;

  /// Whether the info panel beside the terminal is open.
  final bool showTerminalInfo;

  /// Width of the info panel, set by dragging its edge.
  final double infoPanelWidth;
  static const defaultInfoPanelWidth = 300.0;
  static const minInfoPanelWidth = 240.0;
  static const maxInfoPanelWidth = 560.0;

  final AppLanguage language;

  /// Overview cards at the top of the hosts page.
  final bool showHostOverview;

  /// The host of the most recent successful SSH connection, and when.
  final String? lastConnectedHostId;
  final DateTime? lastConnectedAt;

  AppSettings withLastConnected(String hostId, DateTime at) =>
      _copy(lastConnectedHostId: hostId, lastConnectedAt: at);

  Duration get checkInterval => Duration(seconds: checkIntervalSeconds);

  /// False when the user picked "off": no checks, no status dots.
  bool get checksEnabled => checkIntervalSeconds > 0;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? followSystemAccent,
    int? checkIntervalSeconds,
    ReachabilityMethod? checkMethod,
    int? autoLockMinutes,
    bool? showTerminalInfo,
    double? infoPanelWidth,
    AppLanguage? language,
    bool? showHostOverview,
  }) => _copy(
    themeMode: themeMode,
    followSystemAccent: followSystemAccent,
    checkIntervalSeconds: checkIntervalSeconds,
    checkMethod: checkMethod,
    autoLockMinutes: autoLockMinutes,
    showTerminalInfo: showTerminalInfo,
    infoPanelWidth: infoPanelWidth,
    language: language,
    showHostOverview: showHostOverview,
  );

  AppSettings _copy({
    ThemeMode? themeMode,
    bool? followSystemAccent,
    int? checkIntervalSeconds,
    ReachabilityMethod? checkMethod,
    int? autoLockMinutes,
    bool? showTerminalInfo,
    double? infoPanelWidth,
    AppLanguage? language,
    bool? showHostOverview,
    String? lastConnectedHostId,
    DateTime? lastConnectedAt,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    followSystemAccent: followSystemAccent ?? this.followSystemAccent,
    checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
    checkMethod: checkMethod ?? this.checkMethod,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    showTerminalInfo: showTerminalInfo ?? this.showTerminalInfo,
    infoPanelWidth: infoPanelWidth ?? this.infoPanelWidth,
    language: language ?? this.language,
    showHostOverview: showHostOverview ?? this.showHostOverview,
    lastConnectedHostId: lastConnectedHostId ?? this.lastConnectedHostId,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'followSystemAccent': followSystemAccent,
    'checkIntervalSeconds': checkIntervalSeconds,
    'checkMethod': checkMethod.name,
    'autoLockMinutes': autoLockMinutes,
    'showTerminalInfo': showTerminalInfo,
    'infoPanelWidth': infoPanelWidth,
    'language': language.name,
    'showHostOverview': showHostOverview,
    if (lastConnectedHostId != null) 'lastConnectedHostId': lastConnectedHostId,
    if (lastConnectedAt != null)
      'lastConnectedAt': lastConnectedAt!.toIso8601String(),
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
      checkIntervalSeconds:
          (interval != null && (interval == 0 || interval >= 5))
          ? interval
          : d.checkIntervalSeconds,
      checkMethod:
          ReachabilityMethod.values.asNameMap()[json['checkMethod']] ??
          d.checkMethod,
      autoLockMinutes: (autoLock != null && autoLock >= 0)
          ? autoLock
          : d.autoLockMinutes,
      showTerminalInfo: json['showTerminalInfo'] as bool? ?? d.showTerminalInfo,
      infoPanelWidth:
          ((json['infoPanelWidth'] as num?)?.toDouble() ?? d.infoPanelWidth)
              .clamp(minInfoPanelWidth, maxInfoPanelWidth),
      language: AppLanguage.values.asNameMap()[json['language']] ?? d.language,
      showHostOverview: json['showHostOverview'] as bool? ?? d.showHostOverview,
      lastConnectedHostId: json['lastConnectedHostId'] as String?,
      lastConnectedAt: DateTime.tryParse(
        json['lastConnectedAt'] as String? ?? '',
      ),
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
