import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/navigation.dart';
import '../../widgets/page_scaffold.dart';
import '../terminal/sessions_providers.dart';
import 'host.dart';
import 'host_editor_sheet.dart';
import 'hosts_providers.dart';
import 'reachability.dart';

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

  Future<void> _delete(Host host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('删除 ${host.displayName}？'),
        content: const Text('主机信息和保存的密码、私钥会一起删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(hostsProvider.notifier).remove(host.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(hostsProvider);

    return PageScaffold(
      title: '主机',
      actions: [
        SizedBox(
          width: 280,
          height: _actionHeight,
          child: SearchBar(
            hintText: '搜索主机',
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
            label: const Text('新建主机'),
          ),
        ),
      ],
      child: hosts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '读取主机列表失败',
          message: '$e',
        ),
        data: (data) {
          if (data.hosts.isEmpty && data.groups.isEmpty) {
            return const EmptyState(
              icon: Icons.dns_outlined,
              title: '还没有主机',
              message: '添加一台服务器后，就可以从这里一键连接',
            );
          }
          final sections = buildHostSections(data, _query);
          if (sections.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off,
              title: '没有匹配的主机',
              message: '换个关键词试试',
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
                        onDelete: () => _delete(host),
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
        title: '重命名分组',
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
        title: Text('删除分组“${group.name}”？'),
        content: Text(
          count == 0 ? '这个分组里没有主机。' : '组内 $count 台主机会移到“未分组”，主机本身不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除分组'),
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
                      message: group?.name ?? '未分组',
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        group?.name ?? '未分组',
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
                      tooltip: '分组操作',
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, size: 20),
                      onSelected: (v) => switch (v) {
                        'rename' => onRename?.call(),
                        'delete' => onDelete?.call(),
                        _ => null,
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: Icon(Icons.drive_file_rename_outline),
                            title: Text('重命名分组'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.folder_delete_outlined),
                            title: Text('删除分组'),
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
        '这个分组还没有主机，编辑主机时可以把它放进来',
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
      setState(() => _error = '请输入分组名称');
    } else if (widget.takenNames.contains(name.toLowerCase())) {
      setState(() => _error = '已经有同名的分组');
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
          decoration: InputDecoration(labelText: '分组名称', errorText: _error),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
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
    required this.onDelete,
  });

  final Host host;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
                    const SizedBox(width: 8),
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
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (v) => switch (v) {
                  'connect' => onConnect(),
                  'edit' => onEdit(),
                  'delete' => onDelete(),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'connect',
                    child: ListTile(
                      leading: Icon(Icons.terminal),
                      title: Text('连接'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('编辑'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('删除'),
                    ),
                  ),
                ],
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
    final r =
        ref.watch(reachabilityProvider.select((m) => m[hostId])) ??
        Reachability.unknown;
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (r.state) {
      ReachState.up => (
        const Color(0xFF34C759),
        r.latency == null
            ? '连通'
            : '连通 · ${(r.latency!.inMicroseconds / 1000).toStringAsFixed(0)} ms',
      ),
      ReachState.down => (const Color(0xFFFF3B30), '不通'),
      ReachState.unknown => (scheme.outline, '正在检测…'),
    };
    return Tooltip(
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
    );
  }
}
