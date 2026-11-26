import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/toasts.dart';
import '../hosts/host.dart';
import '../hosts/host_avatar.dart';
import '../hosts/hosts_providers.dart';
import '../terminal/sessions_providers.dart';
import 'onion_editor_sheet.dart';
import 'onion_providers.dart';
import 'onion_route.dart';

const _actionHeight = 44.0;

class OnionPage extends ConsumerStatefulWidget {
  const OnionPage({super.key});

  @override
  ConsumerState<OnionPage> createState() => _OnionPageState();
}

class _OnionPageState extends ConsumerState<OnionPage> {
  String _query = '';

  bool _matches(OnionRoute route, Map<String, Host> hostById) {
    if (_query.isEmpty) return true;
    final q = _query;
    if (route.name.toLowerCase().contains(q) ||
        (route.note?.toLowerCase().contains(q) ?? false)) {
      return true;
    }
    for (final id in route.allHostIds) {
      final h = hostById[id];
      if (h != null &&
          (h.displayName.toLowerCase().contains(q) ||
              h.address.toLowerCase().contains(q) ||
              h.username.toLowerCase().contains(q))) {
        return true;
      }
    }
    return false;
  }

  void _connect(OnionRoute route, Map<String, Host> hostById) {
    final resolved = route.resolve(hostById);
    if (resolved == null) {
      showToast(context.l10n.onionHostMissing, kind: ToastKind.error);
      return;
    }
    ref
        .read(sessionsProvider.notifier)
        .openOnion(
          jumpHosts: resolved.jumps,
          targetHost: resolved.target,
          label: route.displayTitle(hostById),
        );
  }

  Future<void> _copyCommand(
    OnionRoute route,
    Map<String, Host> hostById,
  ) async {
    final cmd = route.sshCommandPreview(hostById);
    final toast = context.l10n.onionCommandCopied;
    await Clipboard.setData(ClipboardData(text: cmd));
    showToast(toast, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final routesAsync = ref.watch(onionRoutesProvider);
    final hosts = ref.watch(hostsProvider).value?.hosts ?? const <Host>[];
    final hostById = {for (final h in hosts) h.id: h};

    return PageScaffold(
      title: l.onionTitle,
      actions: [
        SizedBox(
          width: 260,
          height: _actionHeight,
          child: SearchBar(
            key: const ValueKey('onion-search'),
            hintText: l.searchOnionRoutes,
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
            key: const ValueKey('new-onion-button'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => showOnionEditor(context),
            icon: const Icon(Icons.add),
            label: Text(l.newOnionRoute),
          ),
        ),
      ],
      child: routesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: l.loadOnionFailed,
          message: '$e',
        ),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.layers_outlined,
              title: l.noOnionTitle,
              message: l.noOnionMessage,
            );
          }

          final items = [
            for (final r in all)
              if (_matches(r, hostById)) r,
          ];
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.search_off,
              title: l.onionNoMatchesTitle,
              message: l.noMatchesMessage,
            );
          }

          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 540,
              mainAxisExtent: 204,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final route = items[i];
              return _OnionCard(
                route: route,
                hostById: hostById,
                onConnect: () => _connect(route, hostById),
                onEdit: () => showOnionEditor(context, route: route),
                onCopy: () => _copyCommand(route, hostById),
              );
            },
          );
        },
      ),
    );
  }
}

class _OnionCard extends StatelessWidget {
  const _OnionCard({
    required this.route,
    required this.hostById,
    required this.onConnect,
    required this.onEdit,
    required this.onCopy,
  });

  final OnionRoute route;
  final Map<String, Host> hostById;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolved = route.resolve(hostById);
    final isComplete = resolved != null;
    final title = route.displayTitle(hostById);
    final cliPreview = route.sshCommandPreview(hostById);

    return Card(
      key: ValueKey('onion-card-${route.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isComplete
            ? BorderSide.none
            : BorderSide(color: scheme.error.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onConnect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: Onion icon, card title, hop count badge, edit & connect.
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isComplete
                          ? scheme.primaryContainer
                          : scheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.layers,
                      size: 18,
                      color: isComplete
                          ? scheme.onPrimaryContainer
                          : scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                      l.onionHopsCount(route.hopCount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('onion-edit-${route.id}'),
                    tooltip: l.edit,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                  ),
                  const SizedBox(width: 2),
                  FilledButton.tonalIcon(
                    key: ValueKey('onion-connect-${route.id}'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 34),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: isComplete ? onConnect : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(l.onionConnect),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Row 2: Visual hop chain strip (A → B → C).
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < route.jumpHostIds.length; i++) ...[
                        _HopChip(
                          host: hostById[route.jumpHostIds[i]],
                          stepLabel: '${i + 1}',
                          isTarget: false,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                      _HopChip(
                        host: hostById[route.targetHostId],
                        stepLabel: l.onionTargetBadge,
                        isTarget: true,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Row 3: Missing host warning or note/CLI preview + copy action.
              Row(
                children: [
                  Expanded(
                    child: !isComplete
                        ? Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 15,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l.onionHostMissing,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            (route.note != null &&
                                    route.note!.trim().isNotEmpty)
                                ? route.note!.trim()
                                : cliPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (route.note != null &&
                                    route.note!.trim().isNotEmpty)
                                ? theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  )
                                : TextStyle(
                                    fontFamily: monoFontFamily,
                                    fontFamilyFallback: monoFontFallback,
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                          ),
                  ),
                  IconButton(
                    key: ValueKey('onion-copy-${route.id}'),
                    tooltip: l.onionCopyCommand,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: isComplete ? onCopy : null,
                    icon: const Icon(Icons.content_copy_outlined),
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

class _HopChip extends StatelessWidget {
  const _HopChip({
    required this.host,
    required this.stepLabel,
    required this.isTarget,
  });

  final Host? host;
  final String stepLabel;
  final bool isTarget;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missing = host == null;

    final bg = missing
        ? scheme.errorContainer
        : isTarget
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final fg = missing
        ? scheme.onErrorContainer
        : isTarget
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: isTarget && !missing
            ? Border.all(color: scheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (host != null)
            HostAvatar(host: host!, size: 22)
          else
            Icon(Icons.warning_amber_rounded, size: 16, color: fg),
          const SizedBox(width: 6),
          if (isTarget && !missing) ...[
            Icon(Icons.flag_rounded, size: 13, color: fg),
            const SizedBox(width: 3),
          ] else if (!missing) ...[
            Text(
              '$stepLabel.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 3),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              host?.displayName ?? l.onionMissingHostBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: isTarget ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
