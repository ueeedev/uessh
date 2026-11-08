import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../widgets/app_dropdown.dart';
import '../security/master_password_dialog.dart';
import '../security/vault_controller.dart';
import '../../widgets/page_scaffold.dart';
import 'app_settings.dart';
import 'log_sheet.dart';
import 'settings_providers.dart';
import '../../l10n/l10n.dart';

String formatInterval(int seconds) => seconds == 0
    ? currentL10n.checkOff
    : (seconds < 60
          ? currentL10n.seconds(seconds)
          : currentL10n.minutes(seconds ~/ 60));

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    void update(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);
    final theme = Theme.of(context);

    // Keep a value read from an older settings file selectable.
    final intervals = {
      ...AppSettings.checkIntervalChoices,
      s.checkIntervalSeconds,
    }.toList()..sort();

    return PageScaffold(
      title: context.l10n.navSettings,
      child: ListView(
        children: [
          _SectionTitle(context.l10n.appearance),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: Text(context.l10n.theme),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(context.l10n.themeSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(context.l10n.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(context.l10n.themeDark),
                      ),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) =>
                        update((s) => s.copyWith(themeMode: v.first)),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: Text(context.l10n.systemAccent),
                  subtitle: Text(context.l10n.systemAccentSubtitle),
                  value: s.followSystemAccent,
                  onChanged: (v) =>
                      update((s) => s.copyWith(followSystemAccent: v)),
                ),
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(context.l10n.language),
                  subtitle: Text(context.l10n.languageSubtitle),
                  trailing: AppDropdown<AppLanguage>(
                    key: const ValueKey('language'),
                    width: 160,
                    value: s.language,
                    onChanged: (v) => update((s) => s.copyWith(language: v)),
                    entries: [
                      AppDropdownEntry(
                        value: AppLanguage.system,
                        label: context.l10n.themeSystem,
                      ),
                      // Language names stay in their own language.
                      const AppDropdownEntry(
                        value: AppLanguage.zh,
                        label: '简体中文',
                      ),
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
                  title: Text(context.l10n.showHostOverview),
                  subtitle: Text(context.l10n.showHostOverviewSubtitle),
                  value: s.showHostOverview,
                  onChanged: (v) =>
                      update((s) => s.copyWith(showHostOverview: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(context.l10n.reachability),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(context.l10n.checkInterval),
                  subtitle: Text(
                    s.checksEnabled
                        ? context.l10n.checkIntervalOn
                        : context.l10n.checkIntervalOff,
                  ),
                  trailing: AppDropdown<int>(
                    key: const ValueKey('check-interval'),
                    width: 140,
                    value: s.checkIntervalSeconds,
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
                  child: !s.checksEnabled
                      ? const SizedBox(width: double.infinity)
                      : ListTile(
                          leading: const Icon(Icons.network_ping),
                          title: Text(context.l10n.checkMethod),
                          subtitle: Text(
                            s.checkMethod == ReachabilityMethod.ping
                                ? context.l10n.checkMethodPing
                                : context.l10n.checkMethodSsh,
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
                                label: Text(context.l10n.sshPort),
                              ),
                            ],
                            selected: {s.checkMethod},
                            onSelectionChanged: (v) =>
                                update((s) => s.copyWith(checkMethod: v.first)),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionTitle(context.l10n.security),
          _SecurityCard(autoLockMinutes: s.autoLockMinutes, update: update),
          const SizedBox(height: 24),
          _SectionTitle(context.l10n.diagnostics),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(context.l10n.log),
              subtitle: Text(context.l10n.logSubtitle),
              trailing: FilledButton.tonal(
                key: const ValueKey('open-log'),
                onPressed: () => showLogSheet(context),
                child: Text(context.l10n.viewLog),
              ),
            ),
          ),
          // Part of the page: after the last section, scrolls with it.
          const Padding(
            padding: EdgeInsets.only(top: 32, bottom: 8),
            child: Center(child: AppVersionLabel()),
          ),
        ],
      ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// "uessh 0.1.1 (2)": the version the running app was built with.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty
      ? info.version
      : '${info.version} (${info.buildNumber})';
});

class AppVersionLabel extends ConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    if (version == null) return const SizedBox(height: 16);
    final theme = Theme.of(context);
    return SelectableText(
      'uessh $version',
      key: const ValueKey('app-version'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
