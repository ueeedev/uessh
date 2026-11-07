import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_dropdown.dart';
import '../../widgets/page_scaffold.dart';
import 'app_settings.dart';
import 'settings_providers.dart';

String formatInterval(int seconds) =>
    seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分钟';

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
      title: '设置',
      child: ListView(
        children: [
          const _SectionTitle('外观'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('主题'),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (v) =>
                        update((s) => s.copyWith(themeMode: v.first)),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('使用系统强调色'),
                  subtitle: const Text('关闭后使用 uessh 默认配色'),
                  value: s.followSystemAccent,
                  onChanged: (v) =>
                      update((s) => s.copyWith(followSystemAccent: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('主机连通检测'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('检测间隔'),
                  subtitle: const Text('打开软件时检测一次，之后按这个间隔重复检测'),
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
                ListTile(
                  leading: const Icon(Icons.network_ping),
                  title: const Text('检测方式'),
                  subtitle: Text(
                    s.checkMethod == ReachabilityMethod.ping
                        ? '发送 ping。部分云服务器的安全组会屏蔽 ping，这时会显示为不通'
                        : '尝试连接主机的 SSH 端口，能反映是否可以 SSH 登录',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: SegmentedButton<ReachabilityMethod>(
                    segments: const [
                      ButtonSegment(
                        value: ReachabilityMethod.ping,
                        label: Text('Ping'),
                      ),
                      ButtonSegment(
                        value: ReachabilityMethod.sshPort,
                        label: Text('SSH 端口'),
                      ),
                    ],
                    selected: {s.checkMethod},
                    onSelectionChanged: (v) =>
                        update((s) => s.copyWith(checkMethod: v.first)),
                  ),
                ),
              ],
            ),
          ),
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
