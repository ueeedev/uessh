import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../files/uploads.dart';
import 'host_picker.dart';
import 'sessions_providers.dart';
import 'terminal_page.dart';
import 'terminal_session.dart';
import 'workspace_layout.dart';

/// Dragging a pane (by its header) somewhere.
class PaneDrag {
  const PaneDrag(this.sessionId);
  final String sessionId;
}

/// Dragging a whole tab (from the tab strip) somewhere.
class TabDrag {
  const TabDrag(this.tabId);
  final String tabId;
}

/// Space between panes; also the grab area of the divider.
const paneGap = 8.0;

/// Smallest pane while dragging a divider.
const _minPaneWidth = 200.0;
const _minPaneHeight = 120.0;

/// Each pane keeps one key for its whole life, so moving it around the
/// split tree (or to another tab) moves the live terminal widget instead
/// of rebuilding it: focus, selection and scroll position stay.
final _paneKeys = Expando<GlobalKey>();
GlobalKey paneKey(TerminalSession s) =>
    _paneKeys[s] ??= GlobalKey(debugLabel: 'pane-${s.id}');

/// One tab's workspace: its panes laid out by the split tree, with
/// draggable dividers. [isActive] tells whether keyboard focus belongs
/// here (the page is visible and this is the current tab).
class WorkspaceView extends ConsumerWidget {
  const WorkspaceView({
    super.key,
    required this.tab,
    required this.isActive,
    this.bottomGap = 12,
  });

  final WorkspaceTab tab;
  final bool isActive;

  /// Space below the panes (none when the file panel sits there).
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    Widget pane(String id) {
      final session = state.session(id);
      if (session == null) return const SizedBox.shrink();
      return WorkspacePane(
        key: paneKey(session),
        session: session,
        tab: tab,
        isActive: isActive && tab.focusedId == id,
      );
    }

    Widget node(LayoutNode n, List<int> path) => switch (n) {
      PaneNode(:final sessionId) => pane(sessionId),
      SplitNode() => _SplitView(
        key: ValueKey('split-${tab.id}-${path.join('.')}'),
        tabId: tab.id,
        split: n,
        path: path,
        builder: (i) => node(n.children[i], [...path, i]),
      ),
    };

    final zoomed = tab.zoomedId;
    return Padding(
      key: ValueKey('workspace-${tab.id}'),
      padding: EdgeInsets.fromLTRB(12, 0, 0, bottomGap),
      child: zoomed != null && tab.layout.contains(zoomed)
          ? pane(zoomed)
          : node(tab.layout, const []),
    );
  }
}

/// A split: its children side by side (or stacked) with dividers that
/// can be dragged (double-click: equal sizes).
class _SplitView extends ConsumerStatefulWidget {
  const _SplitView({
    super.key,
    required this.tabId,
    required this.split,
    required this.path,
    required this.builder,
  });

  final String tabId;
  final SplitNode split;
  final List<int> path;
  final Widget Function(int index) builder;

  @override
  ConsumerState<_SplitView> createState() => _SplitViewState();
}

class _SplitViewState extends ConsumerState<_SplitView> {
  /// Weights while a divider is being dragged.
  List<double>? _dragWeights;

  List<double> get _weights => _dragWeights ?? widget.split.weights;

  @override
  Widget build(BuildContext context) {
    final split = widget.split;
    final row = split.axis == SplitAxis.row;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = row ? constraints.maxWidth : constraints.maxHeight;
        final n = split.children.length;
        final space = (extent - paneGap * (n - 1)).clamp(0.0, double.infinity);
        final weights = _weights;
        final children = <Widget>[];
        for (var i = 0; i < n; i++) {
          final size = space * weights[i];
          children.add(
            SizedBox(
              width: row ? size : null,
              height: row ? null : size,
              child: widget.builder(i),
            ),
          );
          if (i < n - 1) {
            children.add(
              _Divider(
                key: ValueKey('divider-${widget.path.join('.')}-$i'),
                axis: split.axis,
                onDrag: (delta) => _drag(i, delta, space),
                onEnd: _commit,
                onDoubleTap: () => ref
                    .read(sessionsProvider.notifier)
                    .resize(widget.tabId, widget.path, List.filled(n, 1 / n)),
              ),
            );
          }
        }
        return Flex(
          direction: row ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  void _drag(int i, double delta, double space) {
    if (space <= 0) return;
    final w = [..._weights];
    final min =
        (widget.split.axis == SplitAxis.row ? _minPaneWidth : _minPaneHeight) /
        space;
    final pair = w[i] + w[i + 1];
    final lo = min.clamp(0.0, pair / 2);
    final next = (w[i] + delta / space).clamp(lo, pair - lo);
    w[i] = next;
    w[i + 1] = pair - next;
    setState(() => _dragWeights = w);
  }

  void _commit() {
    final w = _dragWeights;
    if (w == null) return;
    ref.read(sessionsProvider.notifier).resize(widget.tabId, widget.path, w);
    setState(() => _dragWeights = null);
  }
}

class _Divider extends StatefulWidget {
  const _Divider({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onEnd,
    required this.onDoubleTap,
  });

  final SplitAxis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;
  final VoidCallback onDoubleTap;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = widget.axis == SplitAxis.row;
    final grip = Container(
      width: row ? 4 : 40,
      height: row ? 40 : 4,
      decoration: BoxDecoration(
        color: _dragging ? scheme.primary : scheme.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return MouseRegion(
      cursor: row
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: row
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: row ? (d) => widget.onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: row ? (_) => _end() : null,
        onVerticalDragStart: row
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: row ? null : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: row ? null : (_) => _end(),
        onDoubleTap: widget.onDoubleTap,
        child: SizedBox(
          width: row ? paneGap : null,
          height: row ? null : paneGap,
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _hover || _dragging ? 1 : 0,
              child: grip,
            ),
          ),
        ),
      ),
    );
  }

  void _end() {
    setState(() => _dragging = false);
    widget.onEnd();
  }
}

/// A pane: the terminal card, with a header (when the tab is split) that
/// can be dragged to move the pane, a focus ring, and drop zones for
/// panes and tabs dragged onto it.
class WorkspacePane extends ConsumerStatefulWidget {
  const WorkspacePane({
    super.key,
    required this.session,
    required this.tab,
    required this.isActive,
  });

  final TerminalSession session;
  final WorkspaceTab tab;
  final bool isActive;

  @override
  ConsumerState<WorkspacePane> createState() => _WorkspacePaneState();
}

class _WorkspacePaneState extends ConsumerState<WorkspacePane> {
  /// Where a dragged pane / tab would land (null: nothing over us).
  DropSide? _dropSide;

  /// Files from the computer are being dragged over this pane.
  bool _fileOver = false;

  /// Where they'd go: the shell's folder (null while it's looked up).
  String? _fileDir;
  Future<String?>? _resolving;

  Future<String?> _resolveDir() => _resolving ??= () async {
    try {
      final dir =
          await _session.shellCwd() ?? await (await _session.remoteFs()).home();
      if (mounted) setState(() => _fileDir = dir);
      return dir;
    } catch (_) {
      return null;
    }
  }();

  void _fileEnter() {
    if (!_fileOver) setState(() => _fileOver = true);
    if (_session.status == SessionStatus.connected) _resolveDir();
  }

  void _fileExit() => setState(() {
    _fileOver = false;
    // Look again next time: the shell may have moved.
    _fileDir = null;
    _resolving = null;
  });

  Future<void> _fileDrop(List<DropItem> items) async {
    final dir = _fileDir ?? await _resolveDir();
    _fileExit();
    if (!mounted) return;
    if (dir == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(context.l10n.uploadNotConnected)));
      return;
    }
    await uploadTo(context, ref, _session, dir, dropSources(items));
  }

  TerminalSession get _session => widget.session;

  bool _accepts(Object? data) {
    final state = ref.read(sessionsProvider);
    return switch (data) {
      PaneDrag(:final sessionId) => sessionId != _session.id,
      TabDrag(:final tabId) =>
        tabId != widget.tab.id && state.tabById(tabId) != null,
      _ => false,
    };
  }

  DropSide _sideAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return DropSide.center;
    final local = box.globalToLocal(global);
    return dropSideAt(local, box.size.width, box.size.height);
  }

  void _drop(Object data, DropSide side) {
    final n = ref.read(sessionsProvider.notifier);
    final ok = switch (data) {
      PaneDrag(:final sessionId) => n.movePaneTo(sessionId, _session.id, side),
      TabDrag(:final tabId) => n.mergeTabInto(tabId, _session.id, side),
      _ => true,
    };
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.l10n.workspaceFull)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final split = widget.tab.isSplit;
    final focused = widget.tab.focusedId == _session.id;
    final broadcast = widget.tab.broadcast && split;
    final radius = BorderRadius.circular(
      split ? terminalCardRadius - 4 : terminalCardRadius,
    );
    final ringColor = broadcast ? scheme.tertiary : scheme.primary;

    final card = ClipRRect(
      key: const ValueKey('terminal-card'),
      borderRadius: radius,
      child: ColoredBox(
        color: terminalThemeFor(scheme).background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (split)
              _PaneHeader(session: _session, tab: widget.tab, focused: focused),
            Expanded(
              child: TerminalPane(session: _session, isActive: widget.isActive),
            ),
          ],
        ),
      ),
    );

    final connected = _session.status == SessionStatus.connected;
    return DropTarget(
      // Files dragged in from the computer upload to the shell's folder.
      onDragEntered: (_) => _fileEnter(),
      onDragUpdated: (_) => _fileEnter(),
      onDragExited: (_) => _fileExit(),
      onDragDone: (d) => _fileDrop(d.files),
      child: Listener(
        // Clicking anywhere in a pane makes it the focused one.
        onPointerDown: (_) {
          if (!focused || !widget.isActive) {
            ref.read(sessionsProvider.notifier).activate(_session.id);
          }
        },
        child: DragTarget<Object>(
          onWillAcceptWithDetails: (d) => _accepts(d.data),
          onMove: (d) {
            final side = _sideAt(d.offset);
            if (side != _dropSide) setState(() => _dropSide = side);
          },
          onLeave: (_) => setState(() => _dropSide = null),
          onAcceptWithDetails: (d) {
            final side = _sideAt(d.offset);
            setState(() => _dropSide = null);
            _drop(d.data, side);
          },
          builder: (context, candidates, _) => Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: split && (focused || broadcast)
                      ? Border.all(
                          color: ringColor.withValues(
                            alpha: focused ? 1 : 0.45,
                          ),
                          width: 2,
                        )
                      : null,
                ),
                child: card,
              ),
              if (_dropSide != null && candidates.isNotEmpty)
                _DropPreview(side: _dropSide!, radius: radius),
              if (_fileOver)
                DropOverlay(
                  radius: radius.topLeft.x,
                  label: !connected
                      ? context.l10n.uploadNotConnected
                      : _fileDir == null
                      ? context.l10n.dropResolving
                      : context.l10n.dropToUpload(_fileDir!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Highlights where a dropped pane / tab would go.
class _DropPreview extends StatelessWidget {
  const _DropPreview({required this.side, required this.radius});

  final DropSide side;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final rect = switch (side) {
          DropSide.left => Rect.fromLTWH(0, 0, w / 2, h),
          DropSide.right => Rect.fromLTWH(w / 2, 0, w / 2, h),
          DropSide.top => Rect.fromLTWH(0, 0, w, h / 2),
          DropSide.bottom => Rect.fromLTWH(0, h / 2, w, h / 2),
          DropSide.center => Rect.fromLTWH(w * .15, h * .15, w * .7, h * .7),
        };
        return IgnorePointer(
          child: Stack(
            children: [
              AnimatedPositioned(
                key: const ValueKey('drop-preview'),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                left: rect.left + 4,
                top: rect.top + 4,
                width: rect.width - 8,
                height: rect.height - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: radius,
                  ),
                  child: Center(
                    child: Icon(switch (side) {
                      DropSide.left => Icons.west,
                      DropSide.right => Icons.east,
                      DropSide.top => Icons.north,
                      DropSide.bottom => Icons.south,
                      DropSide.center => Icons.swap_horiz,
                    }, color: scheme.primary),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Header of a pane in a split tab: status, name, and buttons. Drag it
/// to move the pane.
class _PaneHeader extends ConsumerWidget {
  const _PaneHeader({
    required this.session,
    required this.tab,
    required this.focused,
  });

  final TerminalSession session;
  final WorkspaceTab tab;
  final bool focused;

  static const height = 28.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final zoomed = tab.zoomedId == session.id;
    final notifier = ref.read(sessionsProvider.notifier);
    final fg = focused ? scheme.primary : scheme.onSurfaceVariant;

    Widget button(String tip, IconData icon, VoidCallback onTap, {Key? key}) =>
        IconButton(
          key: key,
          tooltip: tip,
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          color: scheme.onSurfaceVariant,
          icon: Icon(icon),
          onPressed: onTap,
        );

    final title = ListenableBuilder(
      listenable: session,
      builder: (context, _) => Row(
        children: [
          SessionStatusDot(status: session.status),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              session.host.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: focused ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (tab.broadcast) ...[
            const SizedBox(width: 6),
            Icon(Icons.cell_tower, size: 14, color: scheme.tertiary),
          ],
        ],
      ),
    );

    return Container(
      key: ValueKey('pane-header-${session.id}'),
      height: height,
      decoration: BoxDecoration(
        color: focused
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.onSurface.withValues(alpha: 0.03),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.only(left: 10, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Draggable<Object>(
              data: PaneDrag(session.id),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: DragChip(label: session.host.displayName),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(height: height, child: title),
              ),
            ),
          ),
          button(
            tab.broadcast ? l.broadcastOff : l.broadcastOn,
            tab.broadcast ? Icons.cell_tower : Icons.podcasts,
            () => notifier.toggleBroadcast(tab.id),
            key: ValueKey('broadcast-${session.id}'),
          ),
          button(
            zoomed ? l.restorePane : l.zoomPane,
            zoomed ? Icons.close_fullscreen : Icons.open_in_full,
            () => notifier.toggleZoom(session.id),
            key: ValueKey('zoom-${session.id}'),
          ),
          button(
            l.closePane,
            Icons.close,
            () => requestCloseSession(context, ref, session),
            key: ValueKey('close-pane-${session.id}'),
          ),
        ],
      ),
    );
  }
}

/// What follows the pointer while dragging a pane or tab.
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.label, this.count = 1});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Transform.translate(
      offset: const Offset(8, 8),
      child: Material(
        color: scheme.secondaryContainer,
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                count > 1 ? Icons.dashboard_outlined : Icons.terminal,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                count > 1 ? '$label · $count' : label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the host picker near [session]'s pane and adds the chosen host
/// as a new pane on [side] of it.
Future<void> splitPane(
  BuildContext context,
  WidgetRef ref,
  TerminalSession session,
  DropSide side,
) async {
  final state = ref.read(sessionsProvider);
  final tab = state.tabOf(session.id);
  if (tab != null && tab.paneIds.length >= maxPanes) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(context.l10n.workspaceFull)));
    return;
  }
  final paneContext = paneKey(session).currentContext ?? context;
  final box = paneContext.findRenderObject() as RenderBox?;
  final anchor = box == null
      ? null
      : Rect.fromLTWH(
          box.localToGlobal(Offset.zero).dx + 16,
          box.localToGlobal(Offset.zero).dy + 4,
          0,
          0,
        );
  final host = await showHostPicker(context, anchor: anchor);
  if (host == null) return;
  ref
      .read(sessionsProvider.notifier)
      .open(host, splitFrom: session.id, side: side);
}
