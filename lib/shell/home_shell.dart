import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/forwarding/forwarding_page.dart';
import '../features/hosts/hosts_page.dart';
import '../features/keys/keys_page.dart';
import '../features/settings/settings_page.dart';
import '../features/snippets/snippets_page.dart';
import '../features/terminal/sessions_providers.dart';
import '../features/terminal/terminal_page.dart';
import '../widgets/fade_through_stack.dart';
import '../widgets/window_drag_area.dart';
import 'navigation.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = {
  AppDestination.hosts: _Destination('主机', Icons.dns_outlined, Icons.dns),
  AppDestination.terminal: _Destination(
    '终端',
    Icons.terminal_outlined,
    Icons.terminal,
  ),
  AppDestination.keys: _Destination('密钥', Icons.key_outlined, Icons.key),
  AppDestination.snippets: _Destination('片段', Icons.code_outlined, Icons.code),
  AppDestination.forwarding: _Destination(
    '转发',
    Icons.swap_horiz_outlined,
    Icons.swap_horiz,
  ),
  AppDestination.settings: _Destination(
    '设置',
    Icons.settings_outlined,
    Icons.settings,
  ),
};

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navigationProvider);
    final sessionCount = ref.watch(
      sessionsProvider.select((s) => s.sessions.length),
    );
    return Scaffold(
      body: Row(
        children: [
          _SideNav(
            current: current,
            sessionCount: sessionCount,
            onSelect: (d) => ref.read(navigationProvider.notifier).go(d),
          ),
          Expanded(
            child: FadeThroughIndexedStack(
              index: current.index,
              children: [
                const HostsPage(),
                TerminalPage(isVisible: current == AppDestination.terminal),
                const KeysPage(),
                const SnippetsPage(),
                const ForwardingPage(),
                const SettingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _navWidth = 188.0;

/// Left navigation. Each destination is one pill-shaped button holding both
/// icon and label (like M3 navigation drawer items), so hover, press and the
/// selected highlight cover the whole row.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.current,
    required this.sessionCount,
    required this.onSelect,
  });

  final AppDestination current;
  final int sessionCount;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        width: _navWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top of the sidebar doubles as the title bar on macOS.
            WindowDragArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16 + trafficLightInset,
                  12,
                  16,
                ),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/branding/logo.png',
                      key: const ValueKey('app-logo'),
                      width: 40,
                      height: 40,
                      filterQuality: FilterQuality.medium,
                      semanticLabel: 'uessh logo',
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'uessh',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final d in AppDestination.values)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: _NavItem(
                  destination: _destinations[d]!,
                  selected: d == current,
                  count: d == AppDestination.terminal ? sessionCount : 0,
                  onTap: () => onSelect(d),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: fg,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Badge.count(
                      count: count,
                      backgroundColor: scheme.primary,
                      textColor: scheme.onPrimary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
