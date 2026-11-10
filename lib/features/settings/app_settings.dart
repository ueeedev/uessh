import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/json_file.dart';
import '../terminal/command_highlight.dart';

/// How host reachability is checked.
enum ReachabilityMethod {
  /// ICMP echo via the system `ping` command.
  ping,

  /// TCP connect to the host's SSH port. Works when ICMP is blocked.
  sshPort,
}

/// UI language; [system] follows the OS (Chinese if it's Chinese,
/// English otherwise).
/// How the file browser shows a folder (as in the macOS Finder).
enum FileViewMode { icons, list, columns, gallery }

/// Side panels of the terminal page.
enum TerminalPanel { info, ai }

/// The two halves of the side panel column: a panel opens in its own half;
/// with both halves in use they share the height.
enum PanelSlot { top, bottom }

extension TerminalPanelSlot on TerminalPanel {
  /// Where this panel opens (matches its button's group on the side rail).
  PanelSlot get slot => switch (this) {
    TerminalPanel.info => PanelSlot.top,
    TerminalPanel.ai => PanelSlot.bottom,
  };
}

enum AppLanguage { system, zh, en }

/// Same shape as the terminal's ReconnectPolicy.
typedef ReconnectSettings = ({bool enabled, int attempts, Duration delay});

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.followSystemAccent = true,
    this.checkIntervalSeconds = defaultCheckInterval,
    this.checkMethod = ReachabilityMethod.ping,
    this.autoLockMinutes = defaultAutoLock,
    this.openPanels = const {},
    this.panelSplit = defaultPanelSplit,
    this.infoPanelWidth = defaultInfoPanelWidth,
    this.language = AppLanguage.system,
    this.showHostOverview = true,
    this.runInBackground = true,
    this.showFilePanel = false,
    this.filePanelHeight = defaultFilePanelHeight,
    this.fileViewMode = FileViewMode.list,
    this.showHiddenFiles = false,
    this.autoReconnect = true,
    this.reconnectAttempts = defaultReconnectAttempts,
    this.reconnectDelaySeconds = defaultReconnectDelay,
    this.syntaxHighlight = true,
    this.highlightColors = const {},
    this.autoCheckUpdates = true,
    this.ignoredUpdateVersion,
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

  /// Side panels open beside the terminal (at most one per [PanelSlot]).
  final Set<TerminalPanel> openPanels;

  /// With both halves open: the top half's share of the height, set by
  /// dragging the line between them.
  final double panelSplit;
  static const defaultPanelSplit = 0.5;
  static const minPanelSplit = 0.15;
  static const maxPanelSplit = 0.85;

  bool get panelsOpen => openPanels.isNotEmpty;

  /// The panel open in [slot], if any.
  TerminalPanel? panelIn(PanelSlot slot) {
    for (final p in openPanels) {
      if (p.slot == slot) return p;
    }
    return null;
  }

  /// Opens [panel] (in place of another one in its half) or, if open,
  /// closes it.
  AppSettings togglePanel(TerminalPanel panel) => _copy(
    openPanels: openPanels.contains(panel)
        ? ({...openPanels}..remove(panel))
        : {
            for (final p in openPanels)
              if (p.slot != panel.slot) p,
            panel,
          },
  );

  AppSettings closePanel(TerminalPanel panel) =>
      _copy(openPanels: {...openPanels}..remove(panel));

  /// Width of the side panels, set by dragging their edge.
  final double infoPanelWidth;
  static const defaultInfoPanelWidth = 300.0;
  static const minInfoPanelWidth = 240.0;
  static const maxInfoPanelWidth = 560.0;

  final AppLanguage language;

  /// Overview cards at the top of the hosts page.
  final bool showHostOverview;

  /// Menu bar / tray icon; closing the window hides it instead of quitting.
  final bool runInBackground;

  /// The file browser below the terminal.
  final bool showFilePanel;
  final double filePanelHeight;
  final FileViewMode fileViewMode;
  final bool showHiddenFiles;

  /// Reconnect by itself after the connection drops.
  final bool autoReconnect;
  final int reconnectAttempts;
  final int reconnectDelaySeconds;

  static const defaultReconnectAttempts = 3;
  static const reconnectAttemptChoices = [1, 2, 3, 5, 10];
  static const defaultReconnectDelay = 3;
  static const reconnectDelayChoices = [1, 3, 5, 10, 30, 60];

  /// Look for a new version on GitHub at startup.
  final bool autoCheckUpdates;

  /// A version the user chose to skip ("忽略此版本"); newer ones still show.
  final String? ignoredUpdateVersion;

  /// Colors the command being typed in the terminal.
  final bool syntaxHighlight;

  /// Colors changed from [defaultHighlightColors] (ARGB).
  final Map<HighlightToken, int> highlightColors;

  int highlightColor(HighlightToken t) =>
      highlightColors[t] ?? defaultHighlightColors[t]!;

  HighlightSettings get highlight => (
    enabled: syntaxHighlight,
    colors: {for (final t in HighlightToken.values) t: highlightColor(t)},
  );

  static const defaultFilePanelHeight = 280.0;
  static const minFilePanelHeight = 160.0;
  static const maxFilePanelHeight = 700.0;

  /// The host of the most recent successful SSH connection, and when.
  final String? lastConnectedHostId;
  final DateTime? lastConnectedAt;

  ReconnectSettings get reconnect => (
    enabled: autoReconnect,
    attempts: reconnectAttempts,
    delay: Duration(seconds: reconnectDelaySeconds),
  );

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
    Set<TerminalPanel>? openPanels,
    double? panelSplit,
    double? infoPanelWidth,
    AppLanguage? language,
    bool? showHostOverview,
    bool? runInBackground,
    bool? showFilePanel,
    double? filePanelHeight,
    FileViewMode? fileViewMode,
    bool? showHiddenFiles,
    bool? autoReconnect,
    int? reconnectAttempts,
    int? reconnectDelaySeconds,
    bool? syntaxHighlight,
    Map<HighlightToken, int>? highlightColors,
    bool? autoCheckUpdates,
    String? ignoredUpdateVersion,
  }) => _copy(
    themeMode: themeMode,
    followSystemAccent: followSystemAccent,
    checkIntervalSeconds: checkIntervalSeconds,
    checkMethod: checkMethod,
    autoLockMinutes: autoLockMinutes,
    openPanels: openPanels,
    panelSplit: panelSplit,
    infoPanelWidth: infoPanelWidth,
    language: language,
    showHostOverview: showHostOverview,
    runInBackground: runInBackground,
    showFilePanel: showFilePanel,
    filePanelHeight: filePanelHeight,
    fileViewMode: fileViewMode,
    showHiddenFiles: showHiddenFiles,
    autoReconnect: autoReconnect,
    reconnectAttempts: reconnectAttempts,
    reconnectDelaySeconds: reconnectDelaySeconds,
    syntaxHighlight: syntaxHighlight,
    highlightColors: highlightColors,
    autoCheckUpdates: autoCheckUpdates,
    ignoredUpdateVersion: ignoredUpdateVersion,
  );

  AppSettings _copy({
    ThemeMode? themeMode,
    bool? followSystemAccent,
    int? checkIntervalSeconds,
    ReachabilityMethod? checkMethod,
    int? autoLockMinutes,
    Set<TerminalPanel>? openPanels,
    double? panelSplit,
    double? infoPanelWidth,
    AppLanguage? language,
    bool? showHostOverview,
    bool? runInBackground,
    bool? showFilePanel,
    double? filePanelHeight,
    FileViewMode? fileViewMode,
    bool? showHiddenFiles,
    bool? autoReconnect,
    int? reconnectAttempts,
    int? reconnectDelaySeconds,
    bool? syntaxHighlight,
    Map<HighlightToken, int>? highlightColors,
    bool? autoCheckUpdates,
    String? ignoredUpdateVersion,
    String? lastConnectedHostId,
    DateTime? lastConnectedAt,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    followSystemAccent: followSystemAccent ?? this.followSystemAccent,
    checkIntervalSeconds: checkIntervalSeconds ?? this.checkIntervalSeconds,
    checkMethod: checkMethod ?? this.checkMethod,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    openPanels: openPanels ?? this.openPanels,
    panelSplit: panelSplit ?? this.panelSplit,
    infoPanelWidth: infoPanelWidth ?? this.infoPanelWidth,
    language: language ?? this.language,
    showHostOverview: showHostOverview ?? this.showHostOverview,
    runInBackground: runInBackground ?? this.runInBackground,
    showFilePanel: showFilePanel ?? this.showFilePanel,
    filePanelHeight: filePanelHeight ?? this.filePanelHeight,
    fileViewMode: fileViewMode ?? this.fileViewMode,
    showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
    reconnectDelaySeconds: reconnectDelaySeconds ?? this.reconnectDelaySeconds,
    syntaxHighlight: syntaxHighlight ?? this.syntaxHighlight,
    highlightColors: highlightColors ?? this.highlightColors,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    ignoredUpdateVersion: ignoredUpdateVersion ?? this.ignoredUpdateVersion,
    lastConnectedHostId: lastConnectedHostId ?? this.lastConnectedHostId,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'followSystemAccent': followSystemAccent,
    'checkIntervalSeconds': checkIntervalSeconds,
    'checkMethod': checkMethod.name,
    'autoLockMinutes': autoLockMinutes,
    'openPanels': [for (final p in openPanels) p.name],
    'panelSplit': panelSplit,
    'infoPanelWidth': infoPanelWidth,
    'language': language.name,
    'showHostOverview': showHostOverview,
    'runInBackground': runInBackground,
    'showFilePanel': showFilePanel,
    'filePanelHeight': filePanelHeight,
    'fileViewMode': fileViewMode.name,
    'showHiddenFiles': showHiddenFiles,
    'autoReconnect': autoReconnect,
    'reconnectAttempts': reconnectAttempts,
    'reconnectDelaySeconds': reconnectDelaySeconds,
    'syntaxHighlight': syntaxHighlight,
    'autoCheckUpdates': autoCheckUpdates,
    if (ignoredUpdateVersion != null)
      'ignoredUpdateVersion': ignoredUpdateVersion,
    if (highlightColors.isNotEmpty)
      'highlightColors': {
        for (final e in highlightColors.entries) e.key.name: e.value,
      },
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
      openPanels: _openPanelsFrom(json),
      panelSplit: ((json['panelSplit'] as num?)?.toDouble() ?? d.panelSplit)
          .clamp(minPanelSplit, maxPanelSplit),
      infoPanelWidth:
          ((json['infoPanelWidth'] as num?)?.toDouble() ?? d.infoPanelWidth)
              .clamp(minInfoPanelWidth, maxInfoPanelWidth),
      language: AppLanguage.values.asNameMap()[json['language']] ?? d.language,
      showHostOverview: json['showHostOverview'] as bool? ?? d.showHostOverview,
      runInBackground: json['runInBackground'] as bool? ?? d.runInBackground,
      showFilePanel: json['showFilePanel'] as bool? ?? d.showFilePanel,
      filePanelHeight:
          ((json['filePanelHeight'] as num?)?.toDouble() ?? d.filePanelHeight)
              .clamp(minFilePanelHeight, maxFilePanelHeight),
      fileViewMode:
          FileViewMode.values.asNameMap()[json['fileViewMode']] ??
          d.fileViewMode,
      showHiddenFiles: json['showHiddenFiles'] as bool? ?? d.showHiddenFiles,
      autoReconnect: json['autoReconnect'] as bool? ?? d.autoReconnect,
      reconnectAttempts:
          ((json['reconnectAttempts'] as num?)?.toInt() ?? d.reconnectAttempts)
              .clamp(1, 100),
      reconnectDelaySeconds:
          ((json['reconnectDelaySeconds'] as num?)?.toInt() ??
                  d.reconnectDelaySeconds)
              .clamp(1, 3600),
      syntaxHighlight: json['syntaxHighlight'] as bool? ?? d.syntaxHighlight,
      autoCheckUpdates: json['autoCheckUpdates'] as bool? ?? d.autoCheckUpdates,
      ignoredUpdateVersion: json['ignoredUpdateVersion'] as String?,
      highlightColors: {
        if (json['highlightColors'] case final Map<Object?, Object?> m)
          for (final e in m.entries)
            if (HighlightToken.values.asNameMap()[e.key] case final t?)
              if (e.value case final int v) t: v,
      },
      lastConnectedHostId: json['lastConnectedHostId'] as String?,
      lastConnectedAt: DateTime.tryParse(
        json['lastConnectedAt'] as String? ?? '',
      ),
    );
  }
}

/// Open side panels; settings from 0.1.4 and older had one panel and an
/// open flag ("showTerminalInfo" + "terminalPanel").
Set<TerminalPanel> _openPanelsFrom(Map<String, Object?> json) {
  final names = TerminalPanel.values.asNameMap();
  final list = json['openPanels'];
  if (list is List) {
    final out = <TerminalPanel>{};
    for (final n in list) {
      final p = names[n];
      // One per half.
      if (p != null && out.every((o) => o.slot != p.slot)) out.add(p);
    }
    return out;
  }
  if (json['showTerminalInfo'] == true) {
    return {names[json['terminalPanel']] ?? TerminalPanel.info};
  }
  return const {};
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
