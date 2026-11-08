import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../shell/navigation.dart';
import '../hosts/host.dart';
import '../hosts/host_avatar.dart';
import '../hosts/hosts_page.dart' show ReachabilityDot, buildHostSections;
import '../hosts/hosts_providers.dart';

const _pickerWidth = 360.0;

/// Pops up the host list under [anchor] (a global rect, e.g. the "+"
/// button), or centred near the top when null. Returns the chosen host.
Future<Host?> showHostPicker(BuildContext context, {Rect? anchor}) {
  return showGeneralDialog<Host>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.close,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      final double left = anchor == null
          ? (screen.width - _pickerWidth) / 2
          : anchor.left.clamp(
              8.0,
              math.max(8.0, screen.width - _pickerWidth - 8),
            );
      final top = anchor == null ? 80.0 : anchor.bottom + 6;
      final maxHeight = math.max(
        200.0,
        math.min(460.0, screen.height - top - 16),
      );
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: _pickerWidth,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: const HostPicker(),
            ),
          ),
        ],
      );
    },
    // Grows out of the button: quick fade plus a slight scale.
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween(begin: 0.95, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Searchable, grouped host list. ↑/↓ move the highlight, Enter opens.
class HostPicker extends ConsumerStatefulWidget {
  const HostPicker({super.key});

  @override
  ConsumerState<HostPicker> createState() => _HostPickerState();
}

class _HostPickerState extends ConsumerState<HostPicker> {
  final _search = TextEditingController();
  final _rowKeys = <String, GlobalKey>{};
  String _query = '';
  int _highlight = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _highlight = (_highlight + by) % count);
    final key = _rowKeys.values.elementAtOrNull(_highlight);
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: by > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  void _open(Host host) => Navigator.pop(context, host);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = context.l10n;
    final data = ref.watch(hostsProvider).value ?? const HostsData();
    final sections = buildHostSections(data, _query);
    final hosts = [for (final s in sections) ...s.hosts];
    final showHeaders = data.groups.isNotEmpty;
    if (_highlight >= hosts.length) _highlight = 0;

    _rowKeys.removeWhere((id, _) => !hosts.any((h) => h.id == id));
    for (final h in hosts) {
      _rowKeys.putIfAbsent(h.id, GlobalKey.new);
    }
    // Keep the map in display order for ↑/↓.
    final orderedKeys = {for (final h in hosts) h.id: _rowKeys[h.id]!};
    _rowKeys
      ..clear()
      ..addAll(orderedKeys);

    var index = 0;
    final rows = <Widget>[];
    for (final section in sections) {
      if (showHeaders) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              section.group?.name ?? l.ungrouped,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      for (final host in section.hosts) {
        final i = index++;
        rows.add(
          _HostRow(
            key: _rowKeys[host.id],
            host: host,
            highlighted: i == _highlight,
            onHover: () => setState(() => _highlight = i),
            onTap: () => _open(host),
          ),
        );
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, hosts.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, hosts.length),
      },
      // Soft shadow plus a hairline border, rather than Material
      // elevation (whose shadow drew as a heavy dark rim here).
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          key: const ValueKey('host-picker'),
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(l.pickHostTitle, style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _highlight = 0;
                  }),
                  onSubmitted: (_) {
                    if (hosts.isNotEmpty) _open(hosts[_highlight]);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.searchHosts,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (data.hosts.isEmpty)
                _Empty(
                  title: l.noHostsTitle,
                  action: FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(context);
                      ref
                          .read(navigationProvider.notifier)
                          .go(AppDestination.hosts);
                    },
                    child: Text(l.goAddHost),
                  ),
                )
              else if (hosts.isEmpty)
                _Empty(title: l.noMatchesTitle)
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 6),
                    children: rows,
                  ),
                ),
              if (hosts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    l.pickHostHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({
    super.key,
    required this.host,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final Host host;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: Material(
          color: highlighted ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  HostAvatar(host: host, size: 28),
                  const SizedBox(width: 12),
                  ReachabilityDot(hostId: host.id),
                  Expanded(
                    child: Text(
                      host.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: highlighted
                            ? scheme.onSecondaryContainer
                            : scheme.onSurface,
                      ),
                    ),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
