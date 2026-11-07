import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/shape_morph_indicator.dart';
import '../hosts/host.dart';
import '../hosts/reachability.dart';
import '../settings/settings_providers.dart';
import 'server_stats.dart';
import 'terminal_session.dart';
import '../../l10n/l10n.dart';

const infoPanelWidth = 300.0;

/// Connection details and live server stats for [session], shown beside
/// the terminal. Polls the server every [refreshInterval] while mounted
/// and connected.
class TerminalInfoPanel extends StatefulWidget {
  const TerminalInfoPanel({
    super.key,
    required this.session,
    required this.onClose,
    this.refreshInterval = const Duration(seconds: 5),
  });

  final TerminalSession session;
  final VoidCallback onClose;
  final Duration refreshInterval;

  @override
  State<TerminalInfoPanel> createState() => _TerminalInfoPanelState();
}

class _TerminalInfoPanelState extends State<TerminalInfoPanel> {
  Timer? _timer;
  ServerStats? _stats;
  double? _cpuUsage;
  bool _loading = false;
  bool _failed = false;

  TerminalSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _start();
  }

  @override
  void didUpdateWidget(TerminalInfoPanel old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
      _stats = null;
      _cpuUsage = null;
      _failed = false;
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (_session.status == SessionStatus.connected && _stats == null) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading || _session.status != SessionStatus.connected) {
      if (mounted) setState(() {}); // keep the "connected for" time ticking
      return;
    }
    _loading = true;
    final out = await _session.runCommand(serverStatsCommand);
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (out == null) {
        _failed = _stats == null;
        return;
      }
      final next = ServerStats.parse(out);
      final prev = _stats?.cpuTimes;
      if (prev != null && next.cpuTimes != null) {
        _cpuUsage = next.cpuTimes!.usageSince(prev);
      }
      _stats = next;
      _failed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = _session.status == SessionStatus.connected;
    final stats = _stats;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.info,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.closeInfoPanel,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _ConnectionSection(session: _session),
                const SizedBox(height: 20),
                if (!connected)
                  _Hint(context.l10n.infoAfterConnect)
                else if (stats == null && _failed)
                  _Hint(context.l10n.infoUnavailable)
                else if (stats == null)
                  const _Loading()
                else ...[
                  _Section(
                    title: context.l10n.sectionSystem,
                    rows: [
                      if (stats.hostname != null)
                        (context.l10n.hostname, stats.hostname!),
                      if (stats.os != null)
                        (context.l10n.sectionSystem, stats.os!),
                      if (stats.kernel != null)
                        (context.l10n.kernel, stats.kernel!),
                      if (stats.uptime != null)
                        (context.l10n.uptime, formatDuration(stats.uptime!)),
                      if (stats.cpuCount != null)
                        ('CPU', context.l10n.cpuCores(stats.cpuCount!)),
                      if (stats.load != null)
                        (
                          context.l10n.load,
                          stats.load!
                              .map((v) => v.toStringAsFixed(2))
                              .join('  '),
                        ),
                    ],
                  ),
                  if (stats.hasResources) ...[
                    const SizedBox(height: 20),
                    _SectionTitle(context.l10n.resources),
                    if (stats.cpuTimes != null)
                      _UsageBar(
                        label: 'CPU',
                        fraction: _cpuUsage,
                        detail: _cpuUsage == null
                            ? context.l10n.calculating
                            : '${(_cpuUsage! * 100).toStringAsFixed(0)}%',
                      ),
                    if (stats.memTotal != null && stats.memUsed != null)
                      _UsageBar(
                        label: context.l10n.memory,
                        fraction: stats.memUsed! / stats.memTotal!,
                        detail:
                            '${formatBytes(stats.memUsed!)} / ${formatBytes(stats.memTotal!)}',
                      ),
                    if (stats.diskTotal != null && stats.diskUsed != null)
                      _UsageBar(
                        label: context.l10n.diskRoot,
                        fraction: stats.diskUsed! / stats.diskTotal!,
                        detail:
                            '${formatBytes(stats.diskUsed!)} / ${formatBytes(stats.diskTotal!)}',
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionSection extends ConsumerWidget {
  const _ConnectionSection({required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = session.host;
    final reach = ref.watch(settingsProvider.select((s) => s.checksEnabled))
        ? ref.watch(reachabilityProvider.select((m) => m[host.id]))
        : null;
    final connectedAt = session.connectedAt;
    final status = switch (session.status) {
      SessionStatus.connecting => context.l10n.statusConnecting,
      SessionStatus.connected => context.l10n.statusConnected,
      SessionStatus.failed => context.l10n.statusFailed,
      SessionStatus.closed => context.l10n.statusClosed,
    };
    return _Section(
      title: context.l10n.sectionConnection,
      rows: [
        (context.l10n.fieldName, host.displayName),
        (context.l10n.fieldAddress, host.target),
        (
          context.l10n.auth,
          host.authMethod == AuthMethod.key
              ? context.l10n.authKey
              : context.l10n.authPassword,
        ),
        (context.l10n.status, status),
        if (connectedAt != null)
          (
            context.l10n.statusConnected,
            formatDuration(DateTime.now().difference(connectedAt)),
          ),
        if (reach?.latency != null)
          (
            context.l10n.latency,
            '${(reach!.latency!.inMicroseconds / 1000).round()} ms',
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.fraction,
    required this.detail,
  });

  final String label;
  final double? fraction;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final f = fraction;
    // Turns amber past 70% and red past 90%.
    final color = f == null || f < 0.7
        ? scheme.primary
        : (f < 0.9 ? const Color(0xFFF5A623) : scheme.error);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const Spacer(),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(end: f ?? 0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: f == null ? null : value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ShapeMorphIndicator(size: 20),
        const SizedBox(width: 10),
        _Hint(context.l10n.fetchingInfo),
      ],
    );
  }
}
