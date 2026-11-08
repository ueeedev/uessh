import 'package:flutter/material.dart';

class AppDropdownEntry<T> {
  const AppDropdownEntry({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Text and icon color, for entries that need to stand out (e.g. a
  /// dangerous choice). When selected, the field shows it too, with icon.
  final Color? color;
}

/// M3 outlined dropdown whose menu animates open and closed (it grows from
/// the field and fades), with the arrow turning as it opens.
///
/// Flutter's [DropdownMenu] opens without animation, so this is built on
/// [MenuAnchor] with `animated: true`.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.label,
    this.leadingIcon,
    this.width,
  });

  final T value;
  final List<AppDropdownEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final String? label;
  final IconData? leadingIcon;

  /// Fixed width; when null the field fills the available width.
  final double? width;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _controller = MenuController();
  bool _open = false;

  AppDropdownEntry<T>? get _selected {
    for (final e in widget.entries) {
      if (e.value == widget.value) return e;
    }
    return null;
  }

  void _toggle() =>
      _controller.isOpen ? _controller.close() : _controller.open();

  @override
  Widget build(BuildContext context) {
    final field = LayoutBuilder(
      builder: (context, constraints) =>
          _buildAnchor(context, constraints.maxWidth),
    );
    return widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
  }

  Widget _buildAnchor(BuildContext context, double width) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MenuAnchor(
      controller: _controller,
      animated: true,
      alignmentOffset: const Offset(0, 4),
      onOpen: () => setState(() => _open = true),
      onClose: () => setState(() => _open = false),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
        maximumSize: WidgetStatePropertyAll(Size(width, 320)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        for (final e in widget.entries)
          MenuItemButton(
            style: e.value == widget.value
                ? MenuItemButton.styleFrom(
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                  )
                : null,
            leadingIcon: e.icon == null
                ? null
                : Icon(e.icon, size: 20, color: e.color),
            trailingIcon: e.value == widget.value
                ? const Icon(Icons.check, size: 18)
                : null,
            onPressed: () {
              if (e.value != widget.value) widget.onChanged(e.value);
            },
            child: SizedBox(
              width: width - 80,
              child: Text(
                e.label,
                overflow: TextOverflow.ellipsis,
                style: e.color == null ? null : TextStyle(color: e.color),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          isFocused: _open,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: widget.leadingIcon == null
                ? null
                : Icon(widget.leadingIcon),
            suffixIcon: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: const Icon(Icons.arrow_drop_down),
            ),
          ),
          child: Row(
            children: [
              if (_selected?.color != null && _selected?.icon != null) ...[
                Icon(_selected!.icon, size: 20, color: _selected!.color),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  _selected?.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _selected?.color,
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
