import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'host.dart';
import 'host_avatar.dart';
import 'host_geo.dart';

/// Host editor section for the card icon: letter, symbol or country flag,
/// plus a color for the first two, with a live preview.
class HostIconPicker extends ConsumerStatefulWidget {
  const HostIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.address,
  });

  final HostIcon value;
  final ValueChanged<HostIcon> onChanged;

  /// The editor's name and address fields, for the preview.
  final TextEditingController label;
  final TextEditingController address;

  @override
  ConsumerState<HostIconPicker> createState() => _HostIconPickerState();
}

class _HostIconPickerState extends ConsumerState<HostIconPicker> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.address.addListener(_onAddress);
    if (widget.value.kind == HostIconKind.flag) _lookUp();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.address.removeListener(_onAddress);
    super.dispose();
  }

  void _onAddress() {
    if (widget.value.kind != HostIconKind.flag) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _lookUp);
  }

  /// Fetch the flag for the preview, before the host is saved.
  void _lookUp() {
    final address = widget.address.text.trim();
    if (address.isNotEmpty) {
      ref.read(hostGeoProvider.notifier).request(address);
    }
  }

  void _setKind(HostIconKind kind) {
    widget.onChanged(
      widget.value.copyWith(
        kind: kind,
        symbol: kind == HostIconKind.icon
            ? (widget.value.symbol ?? hostIconChoices.keys.first)
            : null,
      ),
    );
    if (kind == HostIconKind.flag) _lookUp();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final value = widget.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.hostIcon, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([widget.label, widget.address]),
              builder: (context, _) => HostAvatar(
                key: const ValueKey('icon-preview'),
                size: 48,
                icon: value,
                host: Host(
                  id: 'preview',
                  label: widget.label.text.trim(),
                  address: widget.address.text.trim(),
                  port: 22,
                  username: '',
                  authMethod: AuthMethod.password,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SegmentedButton<HostIconKind>(
                key: const ValueKey('icon-kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: HostIconKind.letter,
                    icon: const Icon(Icons.text_fields),
                    label: Text(l.iconLetter),
                  ),
                  ButtonSegment(
                    value: HostIconKind.icon,
                    icon: const Icon(Icons.category_outlined),
                    label: Text(l.iconSymbol),
                  ),
                  ButtonSegment(
                    value: HostIconKind.flag,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(l.iconFlag),
                  ),
                ],
                selected: {value.kind},
                onSelectionChanged: (s) => _setKind(s.first),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.kind == HostIconKind.icon) ...[
                const SizedBox(height: 12),
                _SymbolGrid(
                  selected: value.symbol,
                  color: value.color,
                  onSelected: (s) =>
                      widget.onChanged(value.copyWith(symbol: s)),
                ),
              ],
              if (value.kind != HostIconKind.flag) ...[
                const SizedBox(height: 12),
                _ColorRow(
                  selected: value.color,
                  onSelected: (c) => widget.onChanged(value.copyWith(color: c)),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  l.iconFlagHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SymbolGrid extends StatelessWidget {
  const _SymbolGrid({
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final String? selected;
  final int? color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = hostIconColors(context, color);
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final e in hostIconChoices.entries)
          IconButton(
            key: ValueKey('symbol-${e.key}'),
            isSelected: e.key == selected,
            icon: Icon(e.value, color: scheme.onSurfaceVariant),
            selectedIcon: Icon(e.value, color: fg),
            style: IconButton.styleFrom(
              backgroundColor: e.key == selected ? bg : null,
            ),
            onPressed: () => onSelected(e.key),
          ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ColorDot(
          key: const ValueKey('color-auto'),
          color: null,
          selected: selected == null,
          tooltip: l.iconColorAuto,
          onTap: () => onSelected(null),
        ),
        for (final c in hostColorChoices)
          _ColorDot(
            key: ValueKey('color-$c'),
            color: c,
            selected: selected == c,
            onTap: () => onSelected(c),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final int? color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = hostIconColors(context, color);
    final dot = Material(
      color: bg,
      shape: CircleBorder(
        side: selected
            ? BorderSide(color: scheme.onSurface, width: 2)
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: selected ? 1 : (color == null ? 0.7 : 0),
            child: Icon(
              selected ? Icons.check : Icons.auto_awesome,
              size: 16,
              color: fg,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}
