import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../shell/navigation.dart';
import '../settings/settings_providers.dart';
import '../terminal/sessions_providers.dart';
import 'host.dart';
import 'reachability.dart';

const overviewHeight = 132.0;
const _onlineColor = Color(0xFF2E9E5B);

/// "3 minutes ago", localized.
String formatTimeAgo(AppLocalizations l, DateTime when, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return l.timeJustNow;
  if (d.inHours < 1) return l.timeMinutesAgo(d.inMinutes);
  if (d.inDays < 1) return l.timeHoursAgo(d.inHours);
  return l.timeDaysAgo(d.inDays);
}

/// Cards at the top of the hosts page: one large, two small side by side,
/// one large.
class HostOverview extends ConsumerWidget {
  const HostOverview({super.key, required this.data});

  final HostsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final reach = ref.watch(reachabilityProvider);
    final ids = {for (final h in data.hosts) h.id};
    final online = reach.entries
        .where((e) => ids.contains(e.key) && e.value.state == ReachState.up)
        .length;
    final lost = reach.entries
        .where((e) => ids.contains(e.key) && e.value.state == ReachState.down)
        .length;
    final checks = settings.checksEnabled;

    Host? last;
    for (final h in data.hosts) {
      if (h.id == settings.lastConnectedHostId) last = h;
    }

    return SizedBox(
      height: overviewHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total / online / unreachable share one card.
          Expanded(
            flex: 3,
            child: OverviewSurface(
              key: const ValueKey('overview-stats'),
              accent: scheme.primary,
              shape: OverviewShape.cornerCircle,
              child: Row(
                children: [
                  Expanded(
                    child: OverviewStat(
                      key: const ValueKey('overview-total'),
                      accent: scheme.primary,
                      label: l.overviewTotal,
                      value: '${data.hosts.length}',
                      detail: l.overviewGroups(data.groups.length),
                    ),
                  ),
                  const _StatDivider(),
                  Expanded(
                    child: OverviewStat(
                      key: const ValueKey('overview-online'),
                      accent: _onlineColor,
                      label: l.overviewOnline,
                      value: checks ? '$online' : '—',
                      detail: checks ? null : l.overviewChecksOff,
                    ),
                  ),
                  const _StatDivider(),
                  Expanded(
                    child: OverviewStat(
                      key: const ValueKey('overview-lost'),
                      accent: scheme.error,
                      label: l.overviewLost,
                      value: checks ? '$lost' : '—',
                      detail: checks ? null : l.overviewChecksOff,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _LastConnectedCard(
              host: last,
              at: last == null ? null : settings.lastConnectedAt,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: VerticalDivider(
      width: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// One figure inside the stats card: label on top, big number at the
/// bottom, and a detail line (always reserved, so numbers line up).
class OverviewStat extends StatelessWidget {
  const OverviewStat({
    super.key,
    required this.accent,
    required this.label,
    required this.value,
    this.detail,
  });

  final Color accent;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          maxLines: 1,
          style: theme.textTheme.displaySmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail ?? ' ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LastConnectedCard extends ConsumerWidget {
  const _LastConnectedCard({required this.host, required this.at});

  final Host? host;
  final DateTime? at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final h = host;
    return OverviewCard(
      key: const ValueKey('overview-last'),
      accent: scheme.tertiary,
      shape: OverviewShape.ring,
      label: l.overviewLastConnected,
      value: h?.displayName ?? l.overviewNoRecent,
      valueIsText: true,
      detail: at == null ? null : formatTimeAgo(l, at!),
      trailing: h == null
          ? null
          : FilledButton.tonalIcon(
              key: const ValueKey('overview-connect'),
              onPressed: () {
                ref.read(sessionsProvider.notifier).open(h);
                ref
                    .read(navigationProvider.notifier)
                    .go(AppDestination.terminal);
              },
              icon: const Icon(Icons.terminal, size: 18),
              label: Text(l.connect),
            ),
    );
  }
}

/// A card with a large soft shape in a corner as its background (after the
/// Material 3 "pressed" card look), a label, and a big value.
class OverviewCard extends StatelessWidget {
  const OverviewCard({
    super.key,
    required this.accent,
    required this.label,
    required this.value,
    this.detail,
    this.trailing,
    this.valueIsText = false,
    this.shape = OverviewShape.cornerCircle,
  });

  final Color accent;
  final String label;
  final String value;
  final String? detail;
  final Widget? trailing;

  /// True for a name rather than a number (smaller, ellipsized).
  final bool valueIsText;

  /// The decorative background shape.
  final OverviewShape shape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return OverviewSurface(
      accent: accent,
      shape: shape,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (valueIsText
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.displaySmall)
                          ?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Card background shared by the overview cards: surface colour plus a
/// soft decorative [shape] tinted with [accent], content padded on top.
class OverviewSurface extends StatelessWidget {
  const OverviewSurface({
    super.key,
    required this.accent,
    required this.shape,
    required this.child,
  });

  final Color accent;
  final OverviewShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      child: CustomPaint(
        painter: OverviewShapePainter(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.10),
            scheme.surfaceContainerHigh,
          ),
          shape: shape,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: child,
        ),
      ),
    );
  }
}

/// Background decorations; the two cards use different ones.
enum OverviewShape {
  /// A big circle in the top-right corner, mostly outside the card.
  cornerCircle,

  /// An open ring in the bottom-right corner.
  ring,
}

/// Paints an [OverviewShape] behind an overview card's content. Shapes
/// sit on the right so they stay clear of the text on the left.
class OverviewShapePainter extends CustomPainter {
  const OverviewShapePainter({required this.color, required this.shape});

  final Color color;
  final OverviewShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (shape) {
      case OverviewShape.cornerCircle:
        canvas.drawCircle(Offset(w + h * 0.05, -h * 0.15), h * 0.95, paint);
      case OverviewShape.ring:
        canvas.drawCircle(
          Offset(w - h * 0.15, h * 1.05),
          h * 0.62,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.22,
        );
    }
  }

  @override
  bool shouldRepaint(OverviewShapePainter old) =>
      old.color != color || old.shape != shape;
}
