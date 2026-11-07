import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/side_sheet.dart';
import '../../l10n/l10n.dart';

Future<void> showLogSheet(BuildContext context) =>
    showSideSheet<void>(context, width: 640, builder: (_) => const LogSheet());

/// Live view of the app log, newest at the bottom.
class LogSheet extends StatefulWidget {
  const LogSheet({super.key});

  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  final _scroll = ScrollController();
  bool _errorsOnly = false;

  @override
  void initState() {
    super.initState();
    log.addListener(_onLog);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  void dispose() {
    log.removeListener(_onLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onLog() {
    if (!mounted) return;
    final atBottom =
        !_scroll.hasClients ||
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    setState(() {});
    if (atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: log.export()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.logCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _errorsOnly
        ? log.entries.where((e) => e.level != LogLevel.info).toList()
        : log.entries.toList();
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      height: 1.4,
    );

    return SideSheet(
      title: context.l10n.log,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(context.l10n.warningsOnly),
                  selected: _errorsOnly,
                  onSelected: (v) => setState(() => _errorsOnly = v),
                ),
                const Spacer(),
                Text(
                  context.l10n.logCount(entries.length),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.noLogs,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final color = switch (e.level) {
                            LogLevel.info => scheme.onSurface,
                            LogLevel.warning => const Color(0xFFC77700),
                            LogLevel.error => scheme.error,
                          };
                          return Text(
                            e.format(),
                            style: mono?.copyWith(color: color),
                          );
                        },
                      ),
                    ),
            ),
          ),
          if (log.filePath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: SelectableText(
                context.l10n.logFile(log.filePath!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      leadingActions: [
        TextButton.icon(
          onPressed: log.entries.isEmpty ? null : () => setState(log.clear),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: Text(context.l10n.clear),
        ),
      ],
      actions: [
        FilledButton.tonalIcon(
          onPressed: log.entries.isEmpty ? null : _copy,
          icon: const Icon(Icons.copy),
          label: Text(context.l10n.copyAll),
        ),
      ],
    );
  }
}
