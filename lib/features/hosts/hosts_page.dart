import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/navigation.dart';
import '../../widgets/page_scaffold.dart';
import '../terminal/sessions_providers.dart';
import 'host.dart';
import 'host_editor_sheet.dart';
import 'hosts_providers.dart';
import 'reachability.dart';
import '../settings/settings_providers.dart';
import '../../l10n/l10n.dart';

/// Search bar and "new host" button share this height.
const _actionHeight = 44.0;

class HostsPage extends ConsumerStatefulWidget {
  const HostsPage({super.key});

  @override
  ConsumerState<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends ConsumerState<HostsPage> {
  String _query = '';

  void _connect(Host host) {
    ref.read(sessionsProvider.notifier).open(host);
    ref.read(navigationProvider.notifier).go(AppDestination.terminal);
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostsProvider);

    return PageScaffold(
      title: context.l10n.navHosts,
      actions: [
        SizedBox(
          width: 280,
          height: _actionHeight,
          child: SearchBar(
            hintText: context.l10n.searchHosts,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints.tightFor(height: _actionHeight),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: _actionHeight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => showHostEditor(context),
            icon: const Icon(Icons.add),
            label: Text(context.l10n.newHost),
          ),
        ),
      ],
      child: hosts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: context.l10n.loadHostsFailed,
          message: '$e',
        ),
        data: (data) {
          if (data.hosts.isEmpty && data.groups.isEmpty) {
            return EmptyState(
              icon: Icons.dns_outlined,
              title: context.l10n.noHostsTitle,
              message: context.l10n.noHostsMessage,
            );
          }
          final sections = buildHostSections(data, _query);
          if (sections.isEmpty) {
            return EmptyState(
              icon: Icons.search_off,
              title: context.l10n.noMatchesTitle,
              message: context.l10n.noMatchesMessage,
            );
          }
          // Headers only make sense once there is at least one group.
          final showHeaders = data.groups.isNotEmpty;
          return CustomScrollView(
            slivers: [
              for (final section in sections) ...[
                if (showHeaders)
                  SliverToBoxAdapter(
                    child: GroupHeader(
                      group: section.group,
                      count: section.hosts.length,
                      onRename: section.group == null
                          ? null
                          : () => _renameGroup(data, section.group!),
                      onDelete: section.group == null
                          ? null
                          : () => _deleteGroup(data, section.group!),
                    ),
                  ),
                if (section.hosts.isEmpty)
                  const SliverToBoxAdapter(child: _EmptyGroupHint())
                else
                  SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 340,
                          mainAxisExtent: 72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: section.hosts.length,
                    itemBuilder: (context, i) {
                      final host = section.hosts[i];
                      return HostCard(
                        host: host,
                        onConnect: () => _connect(host),
                        onEdit: () => showHostEditor(context, host: host),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _renameGroup(HostsData data, HostGroup group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => GroupNameDialog(
        title: context.l10n.renameGroup,
        initialName: group.name,
        takenNames: {
          for (final g in data.groups)
            if (g.id != group.id) g.name.toLowerCase(),
        },
      ),
    );
    if (name == null || name == group.name) return;
    await ref.read(hostsProvider.notifier).renameGroup(group.id, name);
  }

  Future<void> _deleteGroup(HostsData data, HostGroup group) async {
    final count = data.hosts.where((h) => h.groupId == group.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.folder_delete_outlined),
        title: Text(context.l10n.deleteGroupTitle(group.name)),
        content: Text(
          count == 0
              ? context.l10n.deleteGroupEmpty
              : context.l10n.deleteGroupBody(count),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.deleteGroup),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(hostsProvider.notifier).deleteGroup(group.id);
    }
  }
}

/// One group's slice of the host list. [group] null = ungrouped.
class HostSection {
  const HostSection(this.group, this.hosts);
  final HostGroup? group;
  final List<Host> hosts;
}

/// Groups in their saved order, then ungrouped hosts. While searching,
/// only sections with matches are kept; a query matching a group's name
/// shows all of that group's hosts.
List<HostSection> buildHostSections(HostsData data, String query) {
  final q = query.trim().toLowerCase();
  bool hostMatches(Host h) =>
      h.label.toLowerCase().contains(q) ||
      h.address.toLowerCase().contains(q) ||
      h.username.toLowerCase().contains(q);

  final sections = <HostSection>[];
  for (final g in data.groups) {
    final inGroup = data.hosts.where((h) => h.groupId == g.id);
    if (q.isEmpty) {
      sections.add(HostSection(g, inGroup.toList())); // keep empty groups
    } else {
      final groupMatches = g.name.toLowerCase().contains(q);
      final hits = groupMatches
          ? inGroup.toList()
          : inGroup.where(hostMatches).toList();
      if (hits.isNotEmpty) sections.add(HostSection(g, hits));
    }
  }
  final ungrouped = data.hosts
      .where((h) => h.groupId == null && (q.isEmpty || hostMatches(h)))
      .toList();
  if (ungrouped.isNotEmpty) sections.add(HostSection(null, ungrouped));
  return sections;
}

/// Section title: group name and host count on the left, a line filling
/// the rest of the row, and a menu for real groups.
/// Longest the name + count area in a group header may get.
const groupLabelMaxWidth = 360.0;

class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.group,
    required this.count,
    this.onRename,
    this.onDelete,
  });

  final HostGroup? group;
  final int count;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            // The line starts right after the label; very long names are
            // capped so a line always remains visible.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: groupLabelMaxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    group == null
                        ? Icons.folder_off_outlined
                        : Icons.folder_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Tooltip(
                      message: group?.name ?? context.l10n.ungrouped,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        group?.name ?? context.l10n.ungrouped,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: scheme.outlineVariant)),
            // Always reserve the menu slot (empty for "ungrouped") so every
            // divider also ends at the same x.
            SizedBox(
              width: 40,
              height: 40,
              child: group == null
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: context.l10n.groupActions,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onSelected: (v) => switch (v) {
                        'rename' => onRename?.call(),
                        'delete' => onDelete?.call(),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: const Icon(
                              Icons.drive_file_rename_outline,
                            ),
                            title: Text(context.l10n.renameGroup),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: const Icon(Icons.folder_delete_outlined),
                            title: Text(context.l10n.deleteGroup),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGroupHint extends StatelessWidget {
  const _EmptyGroupHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 4),
      child: Text(
        context.l10n.emptyGroupHint,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// Asks for a group name; rejects empty names and [takenNames]
/// (lower-case).
class GroupNameDialog extends StatefulWidget {
  const GroupNameDialog({
    super.key,
    required this.title,
    this.initialName = '',
    this.takenNames = const {},
  });

  final String title;
  final String initialName;
  final Set<String> takenNames;

  @override
  State<GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<GroupNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.groupNameRequired);
    } else if (widget.takenNames.contains(name.toLowerCase())) {
      setState(() => _error = context.l10n.groupNameTaken);
    } else {
      Navigator.pop(context, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: context.l10n.groupName,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.ok)),
      ],
    );
  }
}

class HostCard extends StatelessWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.onConnect,
    required this.onEdit,
  });

  final Host host;
  final VoidCallback onConnect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onConnect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(host.displayName.characters.first.toUpperCase()),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    ReachabilityDot(hostId: host.id),
                    Expanded(
                      child: Text(
                        host.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Green: answered the last check. Red: did not. Grey: not checked yet.
class ReachabilityDot extends ConsumerWidget {
  const ReachabilityDot({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checking turned off in settings: no dot at all.
    if (!ref.watch(settingsProvider.select((s) => s.checksEnabled))) {
      return const SizedBox.shrink();
    }
    final r =
        ref.watch(reachabilityProvider.select((m) => m[hostId])) ??
        Reachability.unknown;
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (r.state) {
      ReachState.up => (
        const Color(0xFF34C759),
        r.latency == null
            ? context.l10n.reachUp
            : context.l10n.reachUpLatency(
                (r.latency!.inMicroseconds / 1000).round(),
              ),
      ),
      ReachState.down => (const Color(0xFFFF3B30), context.l10n.reachDown),
      ReachState.unknown => (scheme.outline, context.l10n.reachChecking),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          child: Container(
            key: ValueKey('reach-${r.state.name}'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
