import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/l10n.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/fade_through_stack.dart';
import '../ai/ai_settings.dart';
import '../mcp/mcp_settings_card.dart';
import '../security/master_password_dialog.dart';
import '../security/vault_controller.dart';
import 'app_settings.dart';
import 'highlight_settings.dart';
import 'log_sheet.dart';
import 'proxy_settings_card.dart';
import 'settings_providers.dart';
import 'updates.dart';

/// Width of the left vertical secondary menu inside [SettingsPage].
const settingsSecondaryNavWidth = 204.0;

/// Categories listed vertically in the settings secondary menu.
enum SettingsCategory {
  general,
  appearance,
  reachability,
  ssh,
  proxy,
  ai,
  mcp,
  security,
  diagnostics,
  about,
}

class _CategoryMeta {
  const _CategoryMeta(this.label, this.icon, this.selectedIcon);

  final String Function(AppLocalizations l) label;
  final IconData icon;
  final IconData selectedIcon;
}

final _categoryMeta = {
  SettingsCategory.general: _CategoryMeta(
    (l) => l.general,
    Icons.tune_outlined,
    Icons.tune,
  ),
  SettingsCategory.appearance: _CategoryMeta(
    (l) => l.appearance,
    Icons.palette_outlined,
    Icons.palette,
  ),
  SettingsCategory.reachability: _CategoryMeta(
    (l) => l.reachability,
    Icons.network_check_outlined,
    Icons.network_check,
  ),
  SettingsCategory.ssh: _CategoryMeta(
    (l) => l.sshSection,
    Icons.terminal_outlined,
    Icons.terminal,
  ),
  SettingsCategory.proxy: _CategoryMeta(
    (l) => l.proxySection,
    Icons.public_outlined,
    Icons.public,
  ),
  SettingsCategory.ai: _CategoryMeta(
    (l) => l.aiSection,
    Icons.auto_awesome_outlined,
    Icons.auto_awesome,
  ),
  SettingsCategory.mcp: _CategoryMeta(
    (l) => l.mcpSection,
    Icons.hub_outlined,
    Icons.hub,
  ),
  SettingsCategory.security: _CategoryMeta(
    (l) => l.security,
    Icons.shield_outlined,
    Icons.shield,
  ),
  SettingsCategory.diagnostics: _CategoryMeta(
    (l) => l.diagnostics,
    Icons.receipt_long_outlined,
    Icons.receipt_long,
  ),
  SettingsCategory.about: _CategoryMeta(
    (l) => l.about,
    Icons.info_outline,
    Icons.info,
  ),
};

String formatInterval(int seconds) => seconds == 0
    ? currentL10n.checkOff
    : (seconds < 60
          ? currentL10n.seconds(seconds)
          : currentL10n.minutes(seconds ~/ 60));

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory _selected = SettingsCategory.general;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);

    // Keep a value read from an older settings file selectable.
    final intervals = {
      ...AppSettings.checkIntervalChoices,
      s.checkIntervalSeconds,
    }.toList()..sort();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left vertical secondary menu for settings categories.
        SizedBox(
          width: settingsSecondaryNavWidth,
          child: Material(
            key: const ValueKey('settings-secondary-nav'),
            color: scheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 16, 16),
                  child: Text(
                    l.navSettings,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const ValueKey('settings-secondary-list'),
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    children: [
                      for (final category in SettingsCategory.values)
                        _SecondaryMenuItem(
                          key: ValueKey('settings-nav-${category.name}'),
                          meta: _categoryMeta[category]!,
                          selected: category == _selected,
                          onTap: () => setState(() => _selected = category),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
        // Right pane showing the selected category's settings.
        Expanded(
          child: FadeThroughIndexedStack(
            index: _selected.index,
            duration: const Duration(milliseconds: 220),
            children: [
              for (final category in SettingsCategory.values)
                if (category == SettingsCategory.about)
                  const _AboutPane(key: ValueKey('settings-pane-about'))
                else
                  _CategoryPane(
                    key: ValueKey('settings-pane-${category.name}'),
                    category: category,
                    meta: _categoryMeta[category]!,
                    child: _buildCategoryCard(
                      context: context,
                      category: category,
                      settings: s,
                      intervals: intervals,
                      update: update,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required BuildContext context,
    required SettingsCategory category,
    required AppSettings settings,
    required List<int> intervals,
    required void Function(AppSettings Function(AppSettings)) update,
  }) {
    final l = context.l10n;
    final theme = Theme.of(context);

    return switch (category) {
      SettingsCategory.general => Card(
        child: Column(
          children: [
            SwitchListTile(
              key: const ValueKey('run-in-background'),
              secondary: const Icon(Icons.push_pin_outlined),
              title: Text(l.runInBackground),
              subtitle: Text(l.runInBackgroundSubtitle),
              value: settings.runInBackground,
              onChanged: (v) => update((s) => s.copyWith(runInBackground: v)),
            ),
            SwitchListTile(
              key: const ValueKey('auto-check-updates'),
              secondary: const Icon(Icons.system_update_alt),
              title: Text(l.autoCheckUpdates),
              subtitle: Text(l.autoCheckUpdatesSubtitle),
              value: settings.autoCheckUpdates,
              onChanged: (v) => update((s) => s.copyWith(autoCheckUpdates: v)),
            ),
          ],
        ),
      ),
      SettingsCategory.appearance => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: Text(l.theme),
              trailing: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l.themeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l.themeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l.themeDark),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) =>
                    update((s) => s.copyWith(themeMode: v.first)),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.palette_outlined),
              title: Text(l.systemAccent),
              subtitle: Text(l.systemAccentSubtitle),
              value: settings.followSystemAccent,
              onChanged: (v) =>
                  update((s) => s.copyWith(followSystemAccent: v)),
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(l.language),
              subtitle: Text(l.languageSubtitle),
              trailing: AppDropdown<AppLanguage>(
                key: const ValueKey('language'),
                width: 160,
                value: settings.language,
                onChanged: (v) => update((s) => s.copyWith(language: v)),
                entries: [
                  AppDropdownEntry(
                    value: AppLanguage.system,
                    label: l.themeSystem,
                  ),
                  // Language names stay in their own language.
                  const AppDropdownEntry(value: AppLanguage.zh, label: '简体中文'),
                  const AppDropdownEntry(
                    value: AppLanguage.en,
                    label: 'English',
                  ),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('show-overview'),
              secondary: const Icon(Icons.dashboard_outlined),
              title: Text(l.showHostOverview),
              subtitle: Text(l.showHostOverviewSubtitle),
              value: settings.showHostOverview,
              onChanged: (v) => update((s) => s.copyWith(showHostOverview: v)),
            ),
          ],
        ),
      ),
      SettingsCategory.reachability => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l.checkInterval),
              subtitle: Text(
                settings.checksEnabled ? l.checkIntervalOn : l.checkIntervalOff,
              ),
              trailing: AppDropdown<int>(
                key: const ValueKey('check-interval'),
                width: 140,
                value: settings.checkIntervalSeconds,
                onChanged: (v) =>
                    update((s) => s.copyWith(checkIntervalSeconds: v)),
                entries: [
                  for (final v in intervals)
                    AppDropdownEntry(value: v, label: formatInterval(v)),
                ],
              ),
            ),
            // Method only matters while checking is on.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !settings.checksEnabled
                  ? const SizedBox(width: double.infinity)
                  : ListTile(
                      leading: const Icon(Icons.network_ping),
                      title: Text(l.checkMethod),
                      subtitle: Text(
                        settings.checkMethod == ReachabilityMethod.ping
                            ? l.checkMethodPing
                            : l.checkMethodSsh,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: SegmentedButton<ReachabilityMethod>(
                        segments: [
                          const ButtonSegment(
                            value: ReachabilityMethod.ping,
                            label: Text('Ping'),
                          ),
                          ButtonSegment(
                            value: ReachabilityMethod.sshPort,
                            label: Text(l.sshPort),
                          ),
                        ],
                        selected: {settings.checkMethod},
                        onSelectionChanged: (v) =>
                            update((s) => s.copyWith(checkMethod: v.first)),
                      ),
                    ),
            ),
          ],
        ),
      ),
      SettingsCategory.ssh => Card(
        child: Column(
          children: [
            HighlightSettingsTiles(settings: settings, update: update),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              key: const ValueKey('auto-reconnect'),
              secondary: const Icon(Icons.sync),
              title: Text(l.settingsReconnect),
              subtitle: Text(l.settingsReconnectSubtitle),
              value: settings.autoReconnect,
              onChanged: (v) => update((s) => s.copyWith(autoReconnect: v)),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !settings.autoReconnect
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.replay),
                          title: Text(l.settingsReconnectAttempts),
                          trailing: AppDropdown<int>(
                            key: const ValueKey('reconnect-attempts'),
                            width: 140,
                            value: settings.reconnectAttempts,
                            onChanged: (v) =>
                                update((s) => s.copyWith(reconnectAttempts: v)),
                            entries: [
                              for (final v in {
                                ...AppSettings.reconnectAttemptChoices,
                                settings.reconnectAttempts,
                              }.toList()..sort())
                                AppDropdownEntry(
                                  value: v,
                                  label: l.reconnectAttemptsValue(v),
                                ),
                            ],
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.hourglass_empty),
                          title: Text(l.settingsReconnectDelay),
                          trailing: AppDropdown<int>(
                            key: const ValueKey('reconnect-delay'),
                            width: 140,
                            value: settings.reconnectDelaySeconds,
                            onChanged: (v) => update(
                              (s) => s.copyWith(reconnectDelaySeconds: v),
                            ),
                            entries: [
                              for (final v in {
                                ...AppSettings.reconnectDelayChoices,
                                settings.reconnectDelaySeconds,
                              }.toList()..sort())
                                AppDropdownEntry(
                                  value: v,
                                  label: l.reconnectDelayValue(v),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      SettingsCategory.proxy => const ProxySettingsCard(),
      SettingsCategory.ai => const AiSettingsCard(),
      SettingsCategory.mcp => const McpSettingsCard(),
      SettingsCategory.security => _SecurityCard(
        autoLockMinutes: settings.autoLockMinutes,
        update: update,
      ),
      SettingsCategory.diagnostics => Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(l.log),
          subtitle: Text(l.logSubtitle),
          trailing: FilledButton.tonal(
            key: const ValueKey('open-log'),
            onPressed: () => showLogSheet(context),
            child: Text(l.viewLog),
          ),
        ),
      ),
      SettingsCategory.about => const SizedBox.shrink(),
    };
  }
}

class _SecondaryMenuItem extends StatelessWidget {
  const _SecondaryMenuItem({
    super.key,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final _CategoryMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      selected ? meta.selectedIcon : meta.icon,
                      size: 19,
                      color: fg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        meta.label(context.l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPane extends StatelessWidget {
  const _CategoryPane({
    super.key,
    required this.category,
    required this.meta,
    required this.child,
  });

  final SettingsCategory category;
  final _CategoryMeta meta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = meta.label(context.l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
          child: Row(
            children: [
              Icon(meta.selectedIcon, size: 22, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: ValueKey('settings-content-${category.name}'),
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            children: [child],
          ),
        ),
      ],
    );
  }
}

String formatAutoLock(int minutes) =>
    minutes == 0 ? currentL10n.never : currentL10n.minutes(minutes);

class _SecurityCard extends ConsumerWidget {
  const _SecurityCard({required this.autoLockMinutes, required this.update});

  final int autoLockMinutes;
  final void Function(AppSettings Function(AppSettings)) update;

  Future<void> _open(BuildContext context, MasterPasswordAction action) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MasterPasswordDialog(action: action),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider);
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(context.l10n.masterPassword),
            subtitle: Text(
              vault.hasPassword
                  ? context.l10n.masterPasswordOn
                  : context.l10n.masterPasswordOff,
              style: theme.textTheme.bodySmall,
            ),
            value: vault.hasPassword,
            onChanged: (on) => _open(
              context,
              on ? MasterPasswordAction.set : MasterPasswordAction.remove,
            ),
          ),
          if (vault.hasPassword) ...[
            ListTile(
              leading: const Icon(Icons.password),
              title: Text(context.l10n.changeMasterPassword),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, MasterPasswordAction.change),
            ),
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: Text(context.l10n.autoLock),
              subtitle: Text(context.l10n.autoLockSubtitle),
              trailing: AppDropdown<int>(
                key: const ValueKey('auto-lock'),
                width: 140,
                value: autoLockMinutes,
                onChanged: (v) => update((s) => s.copyWith(autoLockMinutes: v)),
                entries: [
                  for (final m in {
                    ...AppSettings.autoLockChoices,
                    autoLockMinutes,
                  }.toList()..sort())
                    AppDropdownEntry(value: m, label: formatAutoLock(m)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(context.l10n.lockNow),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ref.read(vaultControllerProvider.notifier).lock(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centered About pane showing the app icon, app name, version, and update check.
class _AboutPane extends StatelessWidget {
  const _AboutPane({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      key: const ValueKey('settings-content-about'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/app_icon.png',
              key: const ValueKey('about-app-logo'),
              width: 120,
              height: 120,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'uessh app icon',
            ),
            const SizedBox(height: 12),
            Text(
              'uessh',
              key: const ValueKey('about-app-name'),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const AppVersionLabel(),
            const SizedBox(height: 12),
            const CheckUpdatesLink(),
          ],
        ),
      ),
    );
  }
}

/// "v0.2.0": the version the running app was built with.
final appVersionProvider = FutureProvider<String>((ref) async {
  // Version only; the build number isn't shown.
  return (await PackageInfo.fromPlatform()).version;
});

class AppVersionLabel extends ConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    if (version == null) return const SizedBox(height: 20);
    final theme = Theme.of(context);
    return SelectableText(
      'v$version',
      key: const ValueKey('app-version'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
