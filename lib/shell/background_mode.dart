import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_log.dart';
import '../features/hosts/host.dart';
import '../features/hosts/hosts_providers.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_providers.dart';
import '../features/terminal/sessions_providers.dart';
import '../l10n/l10n.dart';
import 'navigation.dart';

/// What the tray menu should contain; kept free of plugin calls so it can
/// be tested.
class TrayMenuModel {
  const TrayMenuModel({required this.l, required this.hosts});

  final AppLocalizations l;
  final List<Host> hosts;

  /// At most this many hosts in "Quick connect", to keep the menu short.
  static const maxHosts = 15;

  Menu build({
    required VoidCallback onShow,
    required void Function(Host) onConnect,
    required VoidCallback onQuit,
  }) {
    final shown = hosts.take(maxHosts).toList();
    return Menu(
      items: [
        MenuItem(key: 'show', label: l.trayShow, onClick: (_) => onShow()),
        MenuItem.separator(),
        MenuItem.submenu(
          key: 'quick-connect',
          label: l.trayQuickConnect,
          disabled: shown.isEmpty,
          submenu: Menu(
            items: shown.isEmpty
                ? [MenuItem(label: l.noHostsTitle, disabled: true)]
                : [
                    for (final h in shown)
                      MenuItem(
                        key: 'host:${h.id}',
                        label: h.displayName,
                        onClick: (_) => onConnect(h),
                      ),
                  ],
          ),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l.trayQuit, onClick: (_) => onQuit()),
      ],
    );
  }
}

/// Keeps uessh running in the background: a menu bar (macOS) / system
/// tray (Windows) icon with a menu, and closing the window hides it
/// instead of quitting. Follows the "keep running in background" setting.
class BackgroundMode with TrayListener, WindowListener {
  BackgroundMode(this._container);

  final ProviderContainer _container;
  bool _enabled = false;

  bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> start() async {
    windowManager.addListener(this);
    trayManager.addListener(this);
    _container.listen(
      settingsProvider.select((s) => s.runInBackground),
      (_, on) => _apply(on),
      fireImmediately: true,
    );
    // Rebuild the menu when hosts or the language change.
    _container.listen(hostsProvider, (_, _) => _refreshMenu());
    _container.listen(
      settingsProvider.select((s) => s.language),
      (_, _) => _refreshMenu(),
    );
  }

  Future<void> _apply(bool on) async {
    _enabled = on;
    try {
      await windowManager.setPreventClose(on);
      if (on) {
        await trayManager.setIcon(
          _isMac
              ? 'assets/tray/tray_icon_macos.png'
              : 'assets/tray/tray_icon.ico',
          isTemplate: true, // macOS tints it for light/dark menu bars
        );
        if (!_isMac) await trayManager.setToolTip('uessh');
        await _refreshMenu();
      } else {
        await trayManager.destroy();
      }
      log.info('app', 'Background mode ${on ? 'on' : 'off'}');
    } catch (e, st) {
      log.error('app', 'Tray setup failed', e, st);
    }
  }

  AppLocalizations get _l10n {
    final language = _container.read(settingsProvider).language;
    final locale = switch (language) {
      AppLanguage.zh => const Locale('zh'),
      AppLanguage.en => const Locale('en'),
      AppLanguage.system => resolveAppLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      ),
    };
    return lookupAppLocalizations(locale);
  }

  Future<void> _refreshMenu() async {
    if (!_enabled) return;
    final hosts = _container.read(hostsProvider).value?.hosts ?? const [];
    final menu = TrayMenuModel(
      l: _l10n,
      hosts: hosts,
    ).build(onShow: _showWindow, onConnect: _connect, onQuit: _quit);
    await trayManager.setContextMenu(menu);
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _connect(Host host) async {
    _container.read(sessionsProvider.notifier).open(host);
    _container.read(navigationProvider.notifier).go(AppDestination.terminal);
    await _showWindow();
  }

  Future<void> _quit() async {
    log.info('app', 'Quit from tray menu');
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
  }

  // --- WindowListener ---

  @override
  void onWindowClose() {
    // Only reached while preventClose is on, i.e. background mode.
    if (_enabled) windowManager.hide();
  }

  // --- TrayListener ---

  @override
  void onTrayIconMouseDown() {
    // macOS: a click opens the menu, like other menu bar items.
    // Windows: a click brings the window back; right-click for the menu.
    if (_isMac) {
      trayManager.popUpContextMenu();
    } else {
      _showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
}
