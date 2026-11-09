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
import 'navigation.dart';
import '../l10n/l10n.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  /// Looked up at build time so it follows the current language.
  final String Function(AppLocalizations l) label;
  final IconData icon;
  final IconData selectedIcon;
}

final _destinations = {
  AppDestination.hosts: _Destination(
    (l) => l.navHosts,
    Icons.dns_outlined,
    Icons.dns,
  ),
  AppDestination.keys: _Destination(
    (l) => l.navKeys,
    Icons.key_outlined,
    Icons.key,
  ),
  AppDestination.snippets: _Destination(
    (l) => l.navSnippets,
    Icons.code_outlined,
    Icons.code,
  ),
  AppDestination.forwarding: _Destination(
    (l) => l.navForwarding,
    Icons.swap_horiz_outlined,
    Icons.swap_horiz,
  ),
  AppDestination.settings: _Destination(
    (l) => l.navSettings,
    Icons.settings_outlined,
    Icons.settings,
  ),
};

/// The window: a tab strip across the top whose first, pinned tab is the
/// workbench ([HomeView]); the other tabs are SSH workspaces.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: TerminalPage());
}

/// The workbench: navigation on the left and its pages (hosts, keys,
/// snippets, forwarding, settings).
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(navigationProvider);
    return Row(
      children: [
        _SideNav(
          current: current,
          onSelect: (d) => ref.read(navigationProvider.notifier).go(d),
        ),
        Expanded(
          child: FadeThroughIndexedStack(
            index: current.index,
            children: const [
              HostsPage(),
              KeysPage(),
              SnippetsPage(),
              ForwardingPage(),
              SettingsPage(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Width of the workbench's navigation sidebar.
const sideNavWidth = 188.0;

/// Left navigation. Each destination is one pill-shaped button holding both
/// icon and label (like M3 navigation drawer items), so hover, press and the
/// selected highlight cover the whole row.
/// Opens a local terminal (the button above Settings).
const _localTerminal = _Destination(
  _localTerminalLabel,
  Icons.terminal,
  Icons.terminal,
);

String _localTerminalLabel(AppLocalizations l) => l.localTerminal;

class _SideNav extends ConsumerWidget {
  const _SideNav({required this.current, required this.onSelect});

  final AppDestination current;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget item(AppDestination d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: _NavItem(
        destination: _destinations[d]!,
        selected: d == current,
        count: 0,
        onTap: () => onSelect(d),
      ),
    );

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: sideNavWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The tab strip above is the title bar now.
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                child: IgnorePointer(
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
            ),
            for (final d in AppDestination.values)
              if (d != AppDestination.settings) item(d),
            // Settings sits at the bottom, apart from the main pages.
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: _NavItem(
                key: const ValueKey('open-local-terminal'),
                destination: _localTerminal,
                selected: false,
                count: 0,
                onTap: () => ref.read(sessionsProvider.notifier).openLocal(),
              ),
            ),
            item(AppDestination.settings),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
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
                      destination.label(context.l10n),
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
