import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/shape_morph_indicator.dart';
import '../hosts/host.dart';
import '../hosts/reachability.dart';
import 'server_stats.dart';
import 'terminal_session.dart';

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
                Expanded(child: Text('信息', style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: '关闭信息栏',
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
                  _Hint('连接后显示服务器的系统信息')
                else if (stats == null && _failed)
                  _Hint('无法获取系统信息')
                else if (stats == null)
                  const _Loading()
                else ...[
                  _Section(
                    title: '系统',
                    rows: [
                      if (stats.hostname != null) ('主机名', stats.hostname!),
                      if (stats.os != null) ('系统', stats.os!),
                      if (stats.kernel != null) ('内核', stats.kernel!),
                      if (stats.uptime != null)
                        ('运行时间', formatDuration(stats.uptime!)),
                      if (stats.cpuCount != null)
                        ('CPU', '${stats.cpuCount} 核'),
                      if (stats.load != null)
                        (
                          '负载',
                          stats.load!
                              .map((v) => v.toStringAsFixed(2))
                              .join('  '),
                        ),
                    ],
                  ),
                  if (stats.hasResources) ...[
                    const SizedBox(height: 20),
                    _SectionTitle('资源'),
                    if (stats.cpuTimes != null)
                      _UsageBar(
                        label: 'CPU',
                        fraction: _cpuUsage,
                        detail: _cpuUsage == null
                            ? '计算中…'
                            : '${(_cpuUsage! * 100).toStringAsFixed(0)}%',
                      ),
                    if (stats.memTotal != null && stats.memUsed != null)
                      _UsageBar(
                        label: '内存',
                        fraction: stats.memUsed! / stats.memTotal!,
                        detail:
                            '${formatBytes(stats.memUsed!)} / ${formatBytes(stats.memTotal!)}',
                      ),
                    if (stats.diskTotal != null && stats.diskUsed != null)
                      _UsageBar(
                        label: '磁盘 /',
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
    final reach = ref.watch(reachabilityProvider.select((m) => m[host.id]));
    final connectedAt = session.connectedAt;
    final status = switch (session.status) {
      SessionStatus.connecting => '正在连接',
      SessionStatus.connected => '已连接',
      SessionStatus.failed => '连接失败',
      SessionStatus.closed => '已断开',
    };
    return _Section(
      title: '连接',
      rows: [
        ('名称', host.displayName),
        ('地址', host.target),
        ('认证', host.authMethod == AuthMethod.key ? '私钥' : '密码'),
        ('状态', status),
        if (connectedAt != null)
          ('已连接', formatDuration(DateTime.now().difference(connectedAt))),
        if (reach?.latency != null)
          ('延迟', '${(reach!.latency!.inMicroseconds / 1000).round()} ms'),
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
    return const Row(
      children: [
        ShapeMorphIndicator(size: 20),
        SizedBox(width: 10),
        _Hint('正在获取系统信息…'),
      ],
    );
  }
}
