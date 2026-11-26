import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../shell/navigation.dart';
import '../../widgets/page_scaffold.dart';
import '../hosts/host.dart';
import '../hosts/host_avatar.dart';
import '../hosts/hosts_page.dart' show ReachabilityDot, buildHostSections;
import '../hosts/hosts_providers.dart';

/// Opens a modal dialog showing the saved host cards from the Hosts page so
/// the user can pick an intermediate or destination node for an onion route.
Future<Host?> showHostCardPicker(
  BuildContext context, {
  required String title,
  Set<String> usedHostIds = const {},
}) => showDialog<Host>(
  context: context,
  builder: (_) => HostCardPickerDialog(title: title, usedHostIds: usedHostIds),
);

class HostCardPickerDialog extends ConsumerStatefulWidget {
  const HostCardPickerDialog({
    super.key,
    required this.title,
    this.usedHostIds = const {},
  });

  final String title;
  final Set<String> usedHostIds;

  @override
  ConsumerState<HostCardPickerDialog> createState() =>
      _HostCardPickerDialogState();
}

class _HostCardPickerDialogState extends ConsumerState<HostCardPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _goAddHost() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    ref.read(navigationProvider.notifier).go(AppDestination.hosts);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(780.0, math.max(360.0, screen.width - 64));
    final dialogHeight = math.min(560.0, math.max(340.0, screen.height - 96));

    final hostsAsync = ref.watch(hostsProvider);

    return Dialog(
      key: const ValueKey('onion-host-card-picker'),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined, size: 22, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                key: const ValueKey('onion-host-picker-search'),
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.searchHosts,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l.close,
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            // Host card grid matching the Hosts page layout
            Expanded(
              child: hostsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => EmptyState(
                  icon: Icons.error_outline,
                  title: l.loadHostsFailed,
                  message: '$e',
                ),
                data: (data) {
                  if (data.hosts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EmptyState(
                            icon: Icons.dns_outlined,
                            title: l.noHostsTitle,
                            message: l.noHostsMessage,
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: _goAddHost,
                            icon: const Icon(Icons.add),
                            label: Text(l.goAddHost),
                          ),
                        ],
                      ),
                    );
                  }

                  final sections = buildHostSections(
                    data,
                    _query,
                  ).where((s) => s.hosts.isNotEmpty).toList();
                  if (sections.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off,
                      title: l.noMatchesTitle,
                      message: l.noMatchesMessage,
                    );
                  }

                  final showHeaders = data.groups.isNotEmpty;
                  return CustomScrollView(
                    slivers: [
                      const SliverPadding(padding: EdgeInsets.only(top: 12)),
                      for (final section in sections) ...[
                        if (showHeaders)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            sliver: SliverToBoxAdapter(
                              child: _PickerGroupHeader(
                                name: section.group?.name ?? l.ungrouped,
                                isUngrouped: section.group == null,
                                count: section.hosts.length,
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 340,
                                  mainAxisExtent: 78,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: section.hosts.length,
                            itemBuilder: (context, i) {
                              final host = section.hosts[i];
                              return _SelectableHostCard(
                                host: host,
                                alreadyInChain: widget.usedHostIds.contains(
                                  host.id,
                                ),
                                onTap: () => Navigator.pop(context, host),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerGroupHeader extends StatelessWidget {
  const _PickerGroupHeader({
    required this.name,
    required this.isUngrouped,
    required this.count,
  });

  final String name;
  final bool isUngrouped;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(
          isUngrouped ? Icons.folder_off_outlined : Icons.folder_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.outline),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: scheme.outlineVariant)),
      ],
    );
  }
}

class _SelectableHostCard extends StatelessWidget {
  const _SelectableHostCard({
    required this.host,
    required this.alreadyInChain,
    required this.onTap,
  });

  final Host host;
  final bool alreadyInChain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      key: ValueKey('onion-pick-host-${host.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: alreadyInChain
          ? scheme.secondaryContainer.withValues(alpha: 0.4)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: alreadyInChain
              ? scheme.secondary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              HostAvatar(host: host),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ReachabilityDot(hostId: host.id),
                        Expanded(
                          child: Text(
                            host.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (alreadyInChain) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l.onionAlreadyInChain,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
