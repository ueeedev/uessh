import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../terminal/command_highlight.dart';
import 'app_settings.dart';

/// Example line shown above the color choices.
const highlightPreviewCommand =
    r'sudo rm -rf "$HOME/tmp" && ls -la | grep log > out.txt # cleanup';

/// Colors offered for each kind of word.
const highlightPalette = <int>[
  0xFF3FB950, 0xFF7EE787, 0xFF39C5CF, 0xFF58A6FF, 0xFF79C0FF, //
  0xFFBC8CFF, 0xFFD2A8FF, 0xFFFF7EB6, 0xFFF85149, 0xFFFFA657,
  0xFFD29922, 0xFFE3B341, 0xFF8B949E, 0xFFC9D1D9, 0xFF6E7681,
  0xFF0969DA, 0xFF1A7F37, 0xFFCF222E,
];

String highlightTokenLabel(BuildContext context, HighlightToken t) {
  final l = context.l10n;
  return switch (t) {
    HighlightToken.command => l.highlightCommand,
    HighlightToken.dangerous => l.highlightDangerous,
    HighlightToken.option => l.highlightOption,
    HighlightToken.string => l.highlightString,
    HighlightToken.variable => l.highlightVariable,
    HighlightToken.operator => l.highlightOperator,
    HighlightToken.comment => l.highlightComment,
  };
}

/// The on/off switch, a preview and a color for each kind of word.
class HighlightSettingsTiles extends StatelessWidget {
  const HighlightSettingsTiles({
    super.key,
    required this.settings,
    required this.update,
  });

  final AppSettings settings;
  final void Function(AppSettings Function(AppSettings)) update;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l = context.l10n;
    return Column(
      children: [
        SwitchListTile(
          key: const ValueKey('syntax-highlight'),
          secondary: const Icon(Icons.format_color_text),
          title: Text(l.settingsHighlight),
          subtitle: Text(l.settingsHighlightSubtitle),
          value: s.syntaxHighlight,
          onChanged: (v) => update((s) => s.copyWith(syntaxHighlight: v)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !s.syntaxHighlight
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HighlightPreview(colors: s.highlight.colors),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in HighlightToken.values)
                            _ColorChip(
                              token: t,
                              color: s.highlightColor(t),
                              onPick: (c) => update(
                                (s) => s.copyWith(
                                  highlightColors: {...s.highlightColors, t: c}
                                    ..removeWhere(
                                      (k, v) => v == defaultHighlightColors[k],
                                    ),
                                ),
                              ),
                            ),
                          if (s.highlightColors.isNotEmpty)
                            TextButton.icon(
                              key: const ValueKey('highlight-reset'),
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: Text(l.highlightResetAll),
                              onPressed: () => update(
                                (s) => s.copyWith(highlightColors: const {}),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// [highlightPreviewCommand] in a terminal-like box, colored as typed.
class HighlightPreview extends StatelessWidget {
  const HighlightPreview({super.key, required this.colors});

  final Map<HighlightToken, int> colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const text = highlightPreviewCommand;
    final spans = <TextSpan>[];
    var at = 0;
    for (final span in highlightCommand(text)) {
      if (span.start > at) {
        spans.add(TextSpan(text: text.substring(at, span.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(span.start, span.end),
          style: TextStyle(color: Color(colors[span.token]!)),
        ),
      );
      at = span.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Container(
      key: const ValueKey('highlight-preview'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: r'$ ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            ...spans,
          ],
        ),
        style: TextStyle(
          fontFamily: monoFontFamily,
          fontFamilyFallback: monoFontFallback,
          fontSize: 13,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.token,
    required this.color,
    required this.onPick,
  });

  final HighlightToken token;
  final int color;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      key: ValueKey('highlight-${token.name}'),
      avatar: CircleAvatar(backgroundColor: Color(color), radius: 8),
      label: Text(highlightTokenLabel(context, token)),
      onPressed: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (_) => _ColorDialog(token: token, current: color),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

class _ColorDialog extends StatelessWidget {
  const _ColorDialog({required this.token, required this.current});

  final HighlightToken token;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final defaultColor = defaultHighlightColors[token]!;
    final choices = {defaultColor, ...highlightPalette, current};
    return AlertDialog(
      title: Text(highlightTokenLabel(context, token)),
      content: SizedBox(
        width: 280,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in choices)
              InkResponse(
                key: ValueKey('color-${c.toRadixString(16)}'),
                onTap: () => Navigator.pop(context, c),
                radius: 22,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: c == current
                        ? Border.all(color: scheme.onSurface, width: 3)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, defaultColor),
          child: Text(l.highlightDefault),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
