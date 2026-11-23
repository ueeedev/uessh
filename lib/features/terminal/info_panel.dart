import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../widgets/shape_morph_indicator.dart';
import 'server_stats.dart';
import 'terminal_session.dart';
import '../../l10n/l10n.dart';

const infoPanelWidth = 300.0;

/// System information and live server stats for [session], shown beside
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
  int _generation = 0;
  late SessionStatus _status;

  TerminalSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _status = _session.status;
    _session.addListener(_onSessionChanged);
    _start();
  }

  @override
  void didUpdateWidget(TerminalInfoPanel old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSessionChanged);
      _session.addListener(_onSessionChanged);
      _status = _session.status;
      _reset();
      _start();
    } else if (old.refreshInterval != widget.refreshInterval) {
      _start();
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _reset() {
    // An old request may finish after focus changes or a reconnect.
    _generation++;
    _stats = null;
    _cpuUsage = null;
    _loading = false;
    _failed = false;
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_status != _session.status) {
      _status = _session.status;
      _reset();
      _start();
    }
    setState(() {});
  }

  void _start() {
    _timer?.cancel();
    if (_session.status != SessionStatus.connected) return;
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading || _session.status != SessionStatus.connected) return;
    final session = _session;
    final generation = _generation;
    setState(() => _loading = true);
    String? output;
    try {
      output = await session.runCommand(session.statsCommand);
    } catch (_) {
      // A failed sample can be retried on the next tick or manually.
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _failed = output == null || !output.contains('@@end');
      if (_failed) return;
      final next = ServerStats.parse(output!);
      final previous = _stats?.cpuTimes;
      if (next.cpuPercent != null && next.cpuPercent!.isFinite) {
        _cpuUsage = (next.cpuPercent! / 100).clamp(0.0, 1.0);
      } else if (previous != null && next.cpuTimes != null) {
        _cpuUsage = next.cpuTimes!.usageSince(previous);
      } else {
        _cpuUsage = null;
      }
      _stats = next;
    });
  }

  Widget _page(String name, List<Widget> children) => ListView(
    key: PageStorageKey('info-$name-${_session.id}'),
    primary: false,
    padding: const EdgeInsets.all(16),
    children: children,
  );

  Widget _statsPage(String name, Widget Function(ServerStats) content) {
    final stats = _stats;
    return _page(name, [
      if (_session.status != SessionStatus.connected)
        _Hint(context.l10n.infoAfterConnect)
      else if (stats == null)
        if (_failed) _Hint(context.l10n.infoUnavailable) else const _Loading()
      else ...[
        if (_failed) ...[
          _Hint(context.l10n.infoRefreshFailed),
          const SizedBox(height: 16),
        ],
        content(stats),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return DefaultTabController(
      length: 4,
      child: Material(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l.info, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: l.infoRefresh,
                    icon: const Icon(Icons.refresh),
                    onPressed:
                        !_loading && _session.status == SessionStatus.connected
                        ? _refresh
                        : null,
                  ),
                  IconButton(
                    tooltip: l.closeInfoPanel,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            // Secondary tabs divide related content inside the info panel.
            TabBar.secondary(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: theme.textTheme.labelMedium,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                Tab(text: l.infoTabBasic),
                Tab(text: l.infoTabPerformance),
                Tab(text: l.infoTabDisks),
                Tab(text: l.infoTabProcesses),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _statsPage(
                    'basic',
                    (stats) => _BasicInfoSection(stats: stats),
                  ),
                  _statsPage(
                    'performance',
                    (stats) =>
                        _PerformanceSection(stats: stats, cpuUsage: _cpuUsage),
                  ),
                  _statsPage(
                    'disks',
                    (stats) => _DisksSection(disks: stats.disks),
                  ),
                  _statsPage(
                    'processes',
                    (stats) => _ProcessesSection(processes: stats.processes),
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

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.stats, required this.cpuUsage});

  final ServerStats stats;
  final double? cpuUsage;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (!stats.hasResources) return _Hint(l.infoUnavailable);
    final total = stats.memTotal;
    final used = stats.memUsed;
    final memoryUsage = total != null && total > 0 && used != null
        ? used / total
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l.resources),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _UsageCircle(
                key: const ValueKey('cpu-usage-circle'),
                label: 'CPU',
                fraction: cpuUsage,
                calculating: stats.cpuTimes != null && cpuUsage == null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _UsageCircle(
                key: const ValueKey('memory-usage-circle'),
                label: l.memory,
                fraction: memoryUsage,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UsageCircle extends StatelessWidget {
  const _UsageCircle({
    super.key,
    required this.label,
    required this.fraction,
    this.calculating = false,
  });

  final String label;
  final double? fraction;
  final bool calculating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = fraction?.clamp(0.0, 1.0);
    final text = value != null
        ? '${(value * 100).toStringAsFixed(1)}%'
        : (calculating ? context.l10n.calculating : '—');
    return Semantics(
      label: label,
      value: value == null && !calculating
          ? context.l10n.infoUnavailable
          : text,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => SizedBox.square(
                  dimension: constraints.maxWidth.clamp(0.0, 80.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: value ?? 0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        builder: (context, animatedValue, _) =>
                            CircularProgressIndicator(
                              value: calculating ? null : animatedValue,
                              strokeWidth: 5,
                              strokeAlign:
                                  CircularProgressIndicator.strokeAlignInside,
                              strokeCap: StrokeCap.round,
                              color: value != null && value >= 0.9
                                  ? scheme.error
                                  : scheme.primary,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              text,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _DisksSection extends StatelessWidget {
  const _DisksSection({required this.disks});

  final List<DiskStats> disks;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (disks.isEmpty) return _Hint(l.infoUnavailable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final disk in disks) ...[
          Card.filled(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: disk.mountPoint,
                    rows: [
                      (l.infoDevice, disk.device),
                      (l.infoTotal, formatBytes(disk.total)),
                      (l.infoUsed, formatBytes(disk.used)),
                      (l.infoAvailable, formatBytes(disk.available)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _UsageBar(
                    label: l.infoUsage,
                    fraction: disk.used / disk.total,
                    detail:
                        '${(disk.used / disk.total * 100).clamp(0, 100).toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProcessesSection extends StatelessWidget {
  const _ProcessesSection({required this.processes});

  final List<ProcessStats> processes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    if (processes.isEmpty) return _Hint(l.infoUnavailable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l.infoProcessCount(processes.length)),
        _Hint(l.infoProcessesHint),
        const SizedBox(height: 12),
        for (final process in processes) ...[
          Card.filled(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    process.name,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ['PID ${process.pid}', ?process.user].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        'CPU ${process.cpuPercent.toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        '${l.memory} ${formatBytes(process.memoryBytes)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BasicInfoSection extends StatelessWidget {
  const _BasicInfoSection({required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall;
    final platform = stats.platform;
    final platformName = switch (platform) {
      ServerPlatform.windows => 'Windows',
      ServerPlatform.macos => 'macOS',
      ServerPlatform.linux => 'Linux',
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(
          label: l.hostname,
          child: SelectableText(stats.hostname ?? '—', style: style),
        ),
        _InfoRow(
          label: l.os,
          child: SelectionArea(
            child: Text.rich(
              TextSpan(
                text: stats.os ?? '—',
                children: [
                  if (platform != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: SvgPicture.asset(
                          'assets/icons/platforms/${platform.name}.svg',
                          key: ValueKey('system-icon-${platform.name}'),
                          width: 16,
                          height: 16,
                          semanticsLabel: platformName,
                          colorFilter: ColorFilter.mode(
                            Theme.of(context).colorScheme.onSurfaceVariant,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              style: style,
            ),
          ),
        ),
        _InfoRow(
          label: l.kernel,
          child: SelectableText(stats.kernel ?? '—', style: style),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        for (final (label, value) in rows)
          _InfoRow(
            label: label,
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
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
    final f = fraction?.clamp(0.0, 1.0);
    // Use the theme error role for nearly exhausted resources.
    final color = f != null && f >= 0.9 ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
        Expanded(child: _Hint(context.l10n.fetchingInfo)),
      ],
    );
  }
}
