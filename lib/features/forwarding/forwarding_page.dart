import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/shape_morph_indicator.dart';
import '../../widgets/toasts.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import 'forward_editor_sheet.dart';
import 'forwarding_providers.dart';
import 'port_forward.dart';
import 'tunnel_engine.dart';

/// Search bar and primary action buttons share the workbench header height.
const _actionHeight = 44.0;

class ForwardingPage extends ConsumerStatefulWidget {
  const ForwardingPage({super.key});

  @override
  ConsumerState<ForwardingPage> createState() => _ForwardingPageState();
}

class _ForwardingPageState extends ConsumerState<ForwardingPage> {
  String _query = '';
  ForwardType? _typeFilter;
  bool _activeOnly = false;

  bool _matches(PortForwardRule r, Host? host, ForwardRuntimeState runtime) {
    if (_typeFilter != null && r.type != _typeFilter) return false;
    if (_activeOnly && !runtime.isActive) return false;
    if (_query.isEmpty) return true;
    final q = _query;
    return r.name.toLowerCase().contains(q) ||
        r.routeSummary.toLowerCase().contains(q) ||
        r.effectiveBindHost.toLowerCase().contains(q) ||
        '${r.bindPort}'.contains(q) ||
        r.effectiveTargetHost.toLowerCase().contains(q) ||
        (r.targetPort > 0 && '${r.targetPort}'.contains(q)) ||
        (r.note?.toLowerCase().contains(q) ?? false) ||
        (host?.displayName.toLowerCase().contains(q) ?? false) ||
        (host?.address.toLowerCase().contains(q) ?? false);
  }

  Future<void> _copyAddress(
    PortForwardRule rule,
    ForwardRuntimeState runtime,
  ) async {
    final addr = rule.copyableAddress(actualPort: runtime.boundPort);
    final toast = context.l10n.forwardAddressCopied(addr);
    await Clipboard.setData(ClipboardData(text: addr));
    showToast(toast, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final forwardsAsync = ref.watch(portForwardsProvider);
    final runtimeMap = ref.watch(forwardingRuntimeProvider);
    final hosts = ref.watch(hostsProvider).value?.hosts ?? const <Host>[];
    final hostById = {for (final h in hosts) h.id: h};
    final activeCount = runtimeMap.values.where((s) => s.isActive).length;
    final runningCount = runtimeMap.values.where((s) => s.isRunning).length;

    return PageScaffold(
      title: l.forwardingTitle,
      actions: [
        if (activeCount > 0) ...[
          SizedBox(
            height: _actionHeight,
            child: OutlinedButton.icon(
              key: const ValueKey('forward-stop-all'),
              onPressed: () =>
                  ref.read(forwardingRuntimeProvider.notifier).stopAll(),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(l.forwardStopAll),
            ),
          ),
          const SizedBox(width: 12),
        ],
        SizedBox(
          width: 240,
          height: _actionHeight,
          child: SearchBar(
            key: const ValueKey('forwarding-search'),
            hintText: l.searchForwards,
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
            key: const ValueKey('new-forward-button'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => showForwardEditor(context),
            icon: const Icon(Icons.add),
            label: Text(l.newForward),
          ),
        ),
      ],
      child: forwardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: l.loadForwardsFailed,
          message: '$e',
        ),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.swap_horiz,
              title: l.noForwardsTitle,
              message: l.noForwardsMessage,
            );
          }

          final items = [
            for (final r in all)
              if (_matches(
                r,
                hostById[r.hostId],
                runtimeMap[r.id] ?? const ForwardRuntimeState(),
              ))
                r,
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: Text(l.forwardFilterAll),
                          selected: _typeFilter == null && !_activeOnly,
                          onSelected: (_) => setState(() {
                            _typeFilter = null;
                            _activeOnly = false;
                          }),
                        ),
                        for (final t in ForwardType.values)
                          FilterChip(
                            label: Text(forwardTypeLabel(l, t)),
                            selected: _typeFilter == t,
                            onSelected: (selected) => setState(
                              () => _typeFilter = selected ? t : null,
                            ),
                          ),
                        if (activeCount > 0)
                          FilterChip(
                            avatar: Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.green.shade500,
                            ),
                            label: Text(l.forwardFilterActive),
                            selected: _activeOnly,
                            onSelected: (selected) =>
                                setState(() => _activeOnly = selected),
                          ),
                      ],
                    ),
                  ),
                  if (runningCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        l.forwardActiveSummary(runningCount),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: l.forwardNoMatchesTitle,
                        message: l.noMatchesMessage,
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 540,
                              mainAxisExtent: 176,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final rule = items[i];
                          final host = hostById[rule.hostId];
                          final runtime =
                              runtimeMap[rule.id] ??
                              const ForwardRuntimeState();
                          return _ForwardCard(
                            rule: rule,
                            host: host,
                            runtime: runtime,
                            onToggle: () => ref
                                .read(forwardingRuntimeProvider.notifier)
                                .toggle(rule),
                            onCopy: () => _copyAddress(rule, runtime),
                            onEdit: () =>
                                showForwardEditor(context, rule: rule),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForwardCard extends StatelessWidget {
  const _ForwardCard({
    required this.rule,
    required this.host,
    required this.runtime,
    required this.onToggle,
    required this.onCopy,
    required this.onEdit,
  });

  final PortForwardRule rule;
  final Host? host;
  final ForwardRuntimeState runtime;
  final VoidCallback onToggle;
  final VoidCallback onCopy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = forwardTypeVisual(scheme, rule.type);

    final borderColor = switch (runtime.status) {
      ForwardStatus.running => scheme.primary.withValues(alpha: 0.45),
      ForwardStatus.error => scheme.error.withValues(alpha: 0.5),
      _ => Colors.transparent,
    };

    final displayBindPort = runtime.boundPort ?? rule.bindPort;
    final hostLabel = host?.displayName ?? '?';

    return Card(
      key: ValueKey('forward-card-${rule.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderColor == Colors.transparent
            ? BorderSide.none
            : BorderSide(color: borderColor, width: 1.2),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: status dot, type pill, title, controls.
              Row(
                children: [
                  _ForwardStatusDot(status: runtime.status),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: visual.bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(visual.icon, size: 12, color: visual.fg),
                        const SizedBox(width: 3),
                        Text(
                          forwardTypeBadge(l, rule.type),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: visual.fg,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (rule.autoStart) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l.forwardAutoBadge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('forward-copy-${rule.id}'),
                    tooltip: l.forwardCopyAddress,
                    icon: const Icon(Icons.content_copy_outlined, size: 17),
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                  ),
                  IconButton(
                    key: ValueKey('forward-edit-${rule.id}'),
                    tooltip: l.edit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                  ),
                  const SizedBox(width: 2),
                  Tooltip(
                    message: runtime.isActive ? l.forwardStop : l.forwardStart,
                    child: Switch(
                      key: ValueKey('forward-toggle-${rule.id}'),
                      value: runtime.isActive,
                      onChanged:
                          runtime.isStarting ||
                              (host == null && !runtime.isActive)
                          ? null
                          : (_) => onToggle(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: visual tunnel route box.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _RouteDiagram(
                  rule: rule,
                  bindPort: displayBindPort,
                  hostLabel: hostLabel,
                ),
              ),
              const Spacer(),
              // Row 3: live telemetry, error, or host target + note.
              _FooterStatus(rule: rule, host: host, runtime: runtime),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteDiagram extends StatelessWidget {
  const _RouteDiagram({
    required this.rule,
    required this.bindPort,
    required this.hostLabel,
  });

  final PortForwardRule rule;
  final int bindPort;
  final String hostLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final mono = TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      fontSize: 12,
      color: scheme.onSurface,
    );
    final arrow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 14,
        color: scheme.onSurfaceVariant,
      ),
    );

    final (left, middle, right) = switch (rule.type) {
      ForwardType.local => (
        '${rule.effectiveBindHost}:$bindPort',
        hostLabel,
        '${rule.effectiveTargetHost}:${rule.targetPort}',
      ),
      ForwardType.remote => (
        '$hostLabel · ${rule.effectiveBindHost}:$bindPort',
        null,
        '${rule.effectiveTargetHost}:${rule.targetPort}',
      ),
      ForwardType.dynamic => (
        'socks5://${rule.effectiveBindHost}:$bindPort',
        hostLabel,
        l.forwardAnyTarget,
      ),
    };

    return Row(
      children: [
        Flexible(
          flex: 3,
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        arrow,
        if (middle != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              middle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          arrow,
        ],
        Flexible(
          flex: 3,
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono,
          ),
        ),
      ],
    );
  }
}

class _FooterStatus extends StatelessWidget {
  const _FooterStatus({
    required this.rule,
    required this.host,
    required this.runtime,
  });

  final PortForwardRule rule;
  final Host? host;
  final ForwardRuntimeState runtime;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    if (runtime.status == ForwardStatus.error && runtime.error != null) {
      return Tooltip(
        message: runtime.error!,
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 15, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                runtime.error!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ),
      );
    }

    if (runtime.isStarting) {
      return Text(l.forwardStatusStarting, style: subtle);
    }

    if (runtime.isRunning) {
      return Row(
        children: [
          Text(
            l.forwardStatusRunning,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.green.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(l.forwardConnections(runtime.activeConnections), style: subtle),
          const Spacer(),
          Text(
            '↑ ${formatTransferBytes(runtime.bytesUp)}  ↓ ${formatTransferBytes(runtime.bytesDown)}',
            key: ValueKey('forward-traffic-${rule.id}'),
            style: TextStyle(
              fontFamily: monoFontFamily,
              fontFamilyFallback: monoFontFallback,
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (host == null) {
      return Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l.forwardHostMissing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      );
    }

    final parts = [
      host!.target,
      if (rule.note != null && rule.note!.isNotEmpty) rule.note!,
    ];
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: subtle,
    );
  }
}

class _ForwardStatusDot extends StatelessWidget {
  const _ForwardStatusDot({required this.status});

  final ForwardStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    if (status == ForwardStatus.starting) {
      return Tooltip(
        message: l.forwardStatusStarting,
        child: const ShapeMorphIndicator(size: 14),
      );
    }
    final (color, label) = switch (status) {
      ForwardStatus.running => (Colors.green.shade500, l.forwardStatusRunning),
      ForwardStatus.error => (scheme.error, l.forwardStatusError),
      ForwardStatus.stopped => (scheme.outline, l.forwardStatusStopped),
      ForwardStatus.starting => (scheme.tertiary, l.forwardStatusStarting),
    };
    return Tooltip(
      message: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
