import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/side_sheet.dart';
import '../hosts/host.dart';
import '../hosts/host_avatar.dart';
import '../hosts/hosts_providers.dart';
import 'host_card_picker_dialog.dart';
import 'onion_providers.dart';
import 'onion_route.dart';

/// Opens a right-hand side sheet to create or edit an [OnionRoute].
Future<void> showOnionEditor(BuildContext context, {OnionRoute? route}) =>
    showSideSheet<void>(
      context,
      width: 540,
      builder: (_) => OnionEditorSheet(route: route),
    );

class OnionEditorSheet extends ConsumerStatefulWidget {
  const OnionEditorSheet({super.key, this.route});

  final OnionRoute? route;

  @override
  ConsumerState<OnionEditorSheet> createState() => _OnionEditorSheetState();
}

class _OnionEditorSheetState extends ConsumerState<OnionEditorSheet> {
  late final _name = TextEditingController(text: widget.route?.name ?? '');
  late final _note = TextEditingController(text: widget.route?.note ?? '');
  late final List<String> _jumpHostIds = [...?widget.route?.jumpHostIds];
  late String? _targetHostId = widget.route?.targetHostId;

  String? _jumpError;
  String? _targetError;
  bool _saving = false;
  bool _dirty = false;
  late List<Object?> _initial;

  bool get _isEdit => widget.route != null;

  Set<String> get _usedHostIds => {..._jumpHostIds, ?_targetHostId};

  List<Object?> _snapshot() => [
    _name.text,
    _note.text,
    _targetHostId,
    _jumpHostIds.join(','),
  ];

  void _markChanged() {
    final snap = _snapshot();
    final dirty = Iterable<int>.generate(snap.length)
        .any((i) => snap[i] != _initial[i]);
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _initial = _snapshot();
    _name.addListener(_markChanged);
    _note.addListener(_markChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addJumpNode() async {
    final picked = await showHostCardPicker(
      context,
      title: context.l10n.onionPickJumpTitle,
      usedHostIds: _usedHostIds,
    );
    if (picked == null || !mounted) return;
    _jumpHostIds.add(picked.id);
    _jumpError = null;
    _markChanged();
  }

  Future<void> _replaceJumpNode(int index) async {
    final picked = await showHostCardPicker(
      context,
      title: context.l10n.onionPickJumpTitle,
      usedHostIds: _usedHostIds,
    );
    if (picked == null || !mounted) return;
    _jumpHostIds[index] = picked.id;
    _jumpError = null;
    _markChanged();
  }

  void _moveJumpNode(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _jumpHostIds.length) return;
    final id = _jumpHostIds.removeAt(index);
    _jumpHostIds.insert(next, id);
    _markChanged();
  }

  void _removeJumpNode(int index) {
    _jumpHostIds.removeAt(index);
    _markChanged();
  }

  Future<void> _pickTargetNode() async {
    final picked = await showHostCardPicker(
      context,
      title: context.l10n.onionPickTargetTitle,
      usedHostIds: _usedHostIds,
    );
    if (picked == null || !mounted) return;
    _targetHostId = picked.id;
    _targetError = null;
    _markChanged();
  }

  OnionRoute _draftRoute() {
    final note = _note.text.trim();
    return OnionRoute(
      id: widget.route?.id ?? OnionRoute.newId(),
      name: _name.text.trim(),
      jumpHostIds: List.unmodifiable(_jumpHostIds),
      targetHostId: _targetHostId ?? '',
      note: note.isEmpty ? null : note,
      createdAt: widget.route?.createdAt,
    );
  }

  Future<void> _save() async {
    final l = context.l10n;
    final jumpErr = _jumpHostIds.isEmpty ? l.onionNeedJumpError : null;
    final targetErr = (_targetHostId == null || _targetHostId!.isEmpty)
        ? l.onionNeedTargetError
        : null;
    if (jumpErr != null || targetErr != null) {
      setState(() {
        _jumpError = jumpErr;
        _targetError = targetErr;
      });
      return;
    }

    setState(() => _saving = true);
    await ref.read(onionRoutesProvider.notifier).save(_draftRoute());
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete(Map<String, Host> hostById) async {
    final route = widget.route!;
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(l.deleteOnionTitle(route.displayTitle(hostById))),
        content: Text(l.deleteOnionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await ref.read(onionRoutesProvider.notifier).remove(route.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hosts = ref.watch(hostsProvider).value?.hosts ?? const <Host>[];
    final hostById = {for (final h in hosts) h.id: h};

    final targetHost = _targetHostId == null ? null : hostById[_targetHostId!];
    final lastJumpHost = _jumpHostIds.isEmpty
        ? null
        : hostById[_jumpHostIds.last];
    final hasChain = _jumpHostIds.isNotEmpty && _targetHostId != null;
    final preview = hasChain ? _draftRoute().sshCommandPreview(hostById) : null;

    return SideSheet(
      title: _isEdit ? l.editOnionRoute : l.newOnionRoute,
      hasUnsavedChanges: _dirty && !_saving,
      leadingActions: [
        if (_isEdit)
          TextButton.icon(
            key: const ValueKey('delete-onion'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _saving ? null : () => _delete(hostById),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l.delete),
          ),
      ],
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-onion'),
          onPressed: _saving ? null : _save,
          child: Text(l.save),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          TextField(
            key: const ValueKey('onion-name-field'),
            controller: _name,
            decoration: InputDecoration(
              labelText: l.onionName,
              hintText: l.onionNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Local origin indicator
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.laptop_mac,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.onionLocalOrigin,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _ChainArrow(),

          // Intermediate jump nodes section
          Text(
            l.onionJumpNodes,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.onionJumpNodesHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _jumpHostIds.length; i++) ...[
            _JumpNodeTile(
              key: ValueKey('onion-jump-node-$i'),
              index: i,
              total: _jumpHostIds.length,
              host: hostById[_jumpHostIds[i]],
              onMoveUp: i > 0 ? () => _moveJumpNode(i, -1) : null,
              onMoveDown: i < _jumpHostIds.length - 1
                  ? () => _moveJumpNode(i, 1)
                  : null,
              onReplace: () => _replaceJumpNode(i),
              onRemove: () => _removeJumpNode(i),
            ),
            if (i < _jumpHostIds.length - 1) const _ChainArrow(compact: true),
          ],
          if (_jumpHostIds.isNotEmpty) const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('onion-add-jump'),
            onPressed: _addJumpNode,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.onionAddJumpNode),
          ),
          if (_jumpError != null) ...[
            const SizedBox(height: 6),
            Text(
              _jumpError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],

          const _ChainArrow(),

          // Destination / target node section
          Text(
            l.onionTargetNode,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l.onionTargetNodeHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (_targetHostId == null)
            OutlinedButton.icon(
              key: const ValueKey('onion-select-target'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onPressed: _pickTargetNode,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(l.onionSelectTargetNode),
            )
          else
            _TargetNodeTile(
              key: const ValueKey('onion-target-card'),
              host: targetHost,
              onReplace: _pickTargetNode,
            ),
          if (_targetError != null) ...[
            const SizedBox(height: 6),
            Text(
              _targetError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],

          // Visibility note & CLI preview once the chain is formed
          if (hasChain) ...[
            const SizedBox(height: 18),
            if (targetHost != null && lastJumpHost != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.onionVisibilityHint(
                          targetHost.displayName,
                          lastJumpHost.displayName,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              l.onionCliPreview,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              key: const ValueKey('onion-cli-preview'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                preview!,
                style: TextStyle(
                  fontFamily: monoFontFamily,
                  fontFamilyFallback: monoFontFallback,
                  fontSize: 12,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('onion-note-field'),
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l.onionNote,
              hintText: l.onionNoteHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ChainArrow extends StatelessWidget {
  const _ChainArrow({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 3 : 8, horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.arrow_downward_rounded,
            size: compact ? 16 : 18,
            color: scheme.outline,
          ),
        ],
      ),
    );
  }
}

class _JumpNodeTile extends StatelessWidget {
  const _JumpNodeTile({
    super.key,
    required this.index,
    required this.total,
    required this.host,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onReplace,
    required this.onRemove,
  });

  final int index;
  final int total;
  final Host? host;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = host == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: missing
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? scheme.error.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: missing
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l.onionHopBadge(index + 1),
              style: theme.textTheme.labelSmall?.copyWith(
                color: missing
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (host != null)
            HostAvatar(host: host!, size: 32)
          else
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.errorContainer,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: scheme.onErrorContainer,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host?.displayName ?? l.onionMissingHostBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: missing ? scheme.error : null,
                  ),
                ),
                if (host != null)
                  Text(
                    host!.target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (total > 1) ...[
            IconButton(
              key: ValueKey('onion-jump-up-$index'),
              tooltip: l.onionMoveUp,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onMoveUp,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              key: ValueKey('onion-jump-down-$index'),
              tooltip: l.onionMoveDown,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onMoveDown,
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ],
          IconButton(
            key: ValueKey('onion-jump-replace-$index'),
            tooltip: l.onionReplaceNode,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onReplace,
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(
            key: ValueKey('onion-jump-remove-$index'),
            tooltip: l.onionRemoveNode,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _TargetNodeTile extends StatelessWidget {
  const _TargetNodeTile({
    super.key,
    required this.host,
    required this.onReplace,
  });

  final Host? host;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = host == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: missing
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? scheme.error.withValues(alpha: 0.6)
              : scheme.primary.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: missing ? scheme.error : scheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              l.onionTargetBadge,
              style: theme.textTheme.labelSmall?.copyWith(
                color: missing ? scheme.onError : scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (host != null)
            HostAvatar(host: host!, size: 34)
          else
            CircleAvatar(
              radius: 17,
              backgroundColor: scheme.errorContainer,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: scheme.onErrorContainer,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host?.displayName ?? l.onionMissingHostBadge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: missing ? scheme.error : null,
                  ),
                ),
                if (host != null)
                  Text(
                    host!.target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            key: const ValueKey('onion-select-target'),
            onPressed: onReplace,
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: Text(l.onionReplaceNode),
          ),
        ],
      ),
    );
  }
}
