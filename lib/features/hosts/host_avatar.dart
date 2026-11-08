import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'host.dart';
import 'host_geo.dart';

/// Symbols a host can use as its icon, by the key saved in hosts.json.
const hostIconChoices = <String, IconData>{
  'dns': Icons.dns,
  'storage': Icons.storage,
  'cloud': Icons.cloud,
  'computer': Icons.computer,
  'laptop': Icons.laptop_mac,
  'router': Icons.router,
  'lan': Icons.lan,
  'hub': Icons.hub,
  'memory': Icons.memory,
  'terminal': Icons.terminal,
  'code': Icons.code,
  'database': Icons.dataset,
  'public': Icons.public,
  'security': Icons.security,
  'shield': Icons.shield,
  'home': Icons.home,
  'work': Icons.work,
  'rocket': Icons.rocket_launch,
  'science': Icons.science,
  'bug': Icons.bug_report,
  'game': Icons.sports_esports,
  'bolt': Icons.bolt,
  'star': Icons.star,
  'favorite': Icons.favorite,
};

/// Colors a host icon can use. Each is a seed: the avatar uses its M3
/// container / on-container tones, so it fits light and dark themes.
const hostColorChoices = <int>[
  0xFF6750A4, // purple
  0xFF1E88E5, // blue
  0xFF00897B, // teal
  0xFF43A047, // green
  0xFFF9A825, // yellow
  0xFFFB8C00, // orange
  0xFFE53935, // red
  0xFFD81B60, // pink
  0xFF6D4C41, // brown
  0xFF546E7A, // blue grey
];

final _schemes = <(int, Brightness), ColorScheme>{};

/// Background / foreground for a host icon with seed [color] (null: the
/// app's own primary container).
(Color, Color) hostIconColors(BuildContext context, int? color) {
  final theme = Theme.of(context);
  if (color == null) {
    return (
      theme.colorScheme.primaryContainer,
      theme.colorScheme.onPrimaryContainer,
    );
  }
  final scheme = _schemes.putIfAbsent(
    (color, theme.brightness),
    () => ColorScheme.fromSeed(
      seedColor: Color(color),
      brightness: theme.brightness,
    ),
  );
  return (scheme.primaryContainer, scheme.onPrimaryContainer);
}

/// A host's icon: its first letter, a chosen symbol, or the flag of the
/// country its IP is in. A flag host shows its letter until (or unless)
/// the location is known.
class HostAvatar extends ConsumerWidget {
  const HostAvatar({super.key, required this.host, this.size = 40, this.icon});

  final Host host;
  final double size;

  /// Shown instead of [Host.icon] (the editor's live preview).
  final HostIcon? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = this.icon ?? host.icon;
    final geo = icon.kind == HostIconKind.flag
        ? ref.watch(hostGeoProvider.select((m) => m[hostGeoKey(host.address)]))
        : null;
    final svg = geo?.flagSvg;

    final Widget child;
    if (svg != null) {
      child = Tooltip(
        key: ValueKey('flag-${geo!.countryCode}'),
        message: geo.place,
        child: Container(
          width: size,
          height: size,
          decoration: const ShapeDecoration(shape: CircleBorder()),
          // Hairline ring so white flags don't melt into the card.
          foregroundDecoration: ShapeDecoration(
            shape: CircleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SvgPicture.string(
            svg,
            key: const ValueKey('host-flag'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _plain(context, icon),
          ),
        ),
      );
    } else {
      child = KeyedSubtree(
        key: ValueKey('plain-${icon.kind.name}-${icon.symbol}-${icon.color}'),
        child: _plain(context, icon),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
    );
  }

  Widget _plain(BuildContext context, HostIcon icon) {
    final (bg, fg) = hostIconColors(context, icon.color);
    final symbol = icon.kind == HostIconKind.icon
        ? hostIconChoices[icon.symbol]
        : null;
    final name = host.displayName.trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg,
      foregroundColor: fg,
      child: symbol != null
          ? Icon(symbol, key: const ValueKey('host-symbol'), size: size * 0.5)
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.4),
            ),
    );
  }
}
