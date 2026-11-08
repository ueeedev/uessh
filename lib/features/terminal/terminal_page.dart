import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm2/xterm.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/fade_through_stack.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/window_drag_area.dart';
import '../../widgets/shape_morph_indicator.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import 'host_picker.dart';
import 'info_panel.dart';
import 'sessions_providers.dart';
import 'terminal_session.dart';
import '../../l10n/l10n.dart';

class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key, required this.isVisible});

  /// Whether this page is the current navigation destination; used to give
  /// keyboard focus to the active terminal.
  final bool isVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    if (state.sessions.isEmpty) {
      return PageScaffold(
        title: context.l10n.navTerminal,
        child: EmptyState(
          icon: Icons.terminal,
          title: context.l10n.noSessionsTitle,
          message: context.l10n.noSessionsMessage,
          action: Builder(
            builder: (context) => FilledButton.icon(
              key: const ValueKey('empty-new-session'),
              onPressed: () => openHostPicker(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.newSession),
            ),
          ),
        ),
      );
    }

    final activeIndex = state.sessions.indexWhere(
      (s) => s.id == state.activeId,
    );
    final active = state.active ?? state.sessions.first;
    final showInfo = ref.watch(
      settingsProvider.select((s) => s.showTerminalInfo),
    );
    void setInfo(bool v) => ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(showTerminalInfo: v));

    void closeActive() {
      final current = ref.read(sessionsProvider).active;
      if (isVisible && current != null) {
        requestCloseSession(context, ref, current);
      }
    }

    // The terminal maps ⌘W/Ctrl+W to CloseTabIntent itself (so the shell
    // doesn't get it); Shortcuts here cover focus elsewhere on the page.
    return Shortcuts(
      shortcuts: {
        closeTabActivator: const CloseTabIntent(),
        ...switchTabShortcuts,
      },
      child: Actions(
        actions: {
          CloseTabIntent: CallbackAction<CloseTabIntent>(
            onInvoke: (_) {
              closeActive();
              return null;
            },
          ),
          SwitchTabIntent: CallbackAction<SwitchTabIntent>(
            onInvoke: (intent) {
              if (isVisible) switchToTab(ref, intent.number);
              return null;
            },
          ),
        },
        child: _buildBody(
          context,
          ref,
          state,
          activeIndex,
          active,
          showInfo,
          setInfo,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SessionsState state,
    int activeIndex,
    TerminalSession active,
    bool showInfo,
    void Function(bool) setInfo,
  ) {
    // Same colour as the tab strip, so the rounded terminal card and the
    // info panel stand out from it in both light and dark themes.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabStrip(
            state: state,
            infoOpen: showInfo,
            onToggleInfo: () => setInfo(!showInfo),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // Quicker than page switches: tabs are switched often.
                    child: FadeThroughIndexedStack(
                      duration: const Duration(milliseconds: 200),
                      index: activeIndex < 0 ? 0 : activeIndex,
                      children: [
                        for (final s in state.sessions)
                          TerminalPane(
                            key: ValueKey(s.id),
                            session: s,
                            isActive: isVisible && s.id == state.activeId,
                          ),
                      ],
                    ),
                  ),
                  _SlidingPanel(
                    open: showInfo,
                    // The panel may take at most 60% of the terminal page.
                    available: constraints.maxWidth,
                    width: ref.watch(
                      settingsProvider.select((s) => s.infoPanelWidth),
                    ),
                    onWidthChanged: (w) => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(infoPanelWidth: w)),
                    child: TerminalInfoPanel(
                      key: ValueKey('info-${active.id}'),
                      session: active,
                      onClose: () => setInfo(false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides its child in from the right edge; the terminal beside it
/// shrinks to make room rather than being covered.
/// The info panel: slides in from the right edge (the terminal shrinks to
/// make room), and its width can be dragged with the handle between it
/// and the terminal. Double-click the handle for the default width.
class _SlidingPanel extends StatefulWidget {
  const _SlidingPanel({
    required this.open,
    required this.available,
    required this.width,
    required this.onWidthChanged,
    required this.child,
  });

  final bool open;

  /// Width of the whole terminal page.
  final double available;

  /// Saved width; [onWidthChanged] is called once a drag ends.
  final double width;
  final ValueChanged<double> onWidthChanged;
  final Widget child;

  /// The gap left of the panel (holds the handle) and right of it.
  static const gap = 12.0;

  @override
  State<_SlidingPanel> createState() => _SlidingPanelState();
}

class _SlidingPanelState extends State<_SlidingPanel> {
  double? _dragWidth; // live width while dragging
  bool _hover = false;

  double get _width => _dragWidth ?? widget.width;

  double _clamp(double w, double available) {
    final max = (available * 0.6).clamp(
      AppSettings.minInfoPanelWidth,
      AppSettings.maxInfoPanelWidth,
    );
    return w.clamp(AppSettings.minInfoPanelWidth, max);
  }

  @override
  Widget build(BuildContext context) {
    const gap = _SlidingPanel.gap;
    final available = widget.available;
    final width = _clamp(_width, available);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.open ? 1 : 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final panelWidth = (width + gap) * t;
        return SizedBox(
          width: gap + panelWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(context, t == 1, available),
              if (t > 0)
                SizedBox(
                  width: panelWidth,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: width + gap,
                      maxWidth: width + gap,
                      child: Opacity(opacity: t, child: child),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, gap, gap),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(terminalCardRadius),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _handle(BuildContext context, bool active, double available) {
    const gap = _SlidingPanel.gap;
    if (!active) return const SizedBox(width: gap);
    final scheme = Theme.of(context).colorScheme;
    final dragging = _dragWidth != null;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const ValueKey('info-panel-handle'),
        behavior: HitTestBehavior.opaque,
        // Count from the press point, so the edge tracks the pointer
        // exactly (the drag-detection distance isn't lost).
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => setState(() => _dragWidth = widget.width),
        // Dragging left widens the panel.
        onHorizontalDragUpdate: (d) =>
            setState(() => _dragWidth = _clamp(_width - d.delta.dx, available)),
        onHorizontalDragEnd: (_) {
          final w = _clamp(_width, available);
          setState(() => _dragWidth = null);
          widget.onWidthChanged(w);
        },
        onDoubleTap: () =>
            widget.onWidthChanged(AppSettings.defaultInfoPanelWidth),
        child: SizedBox(
          width: gap,
          child: Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _hover || dragging ? 1 : 0,
                child: Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: dragging ? scheme.primary : scheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip behind the tabs is the page colour; the selected tab takes
/// the terminal's background so it reads as the top of that window.
Color tabStripColor(ColorScheme scheme) => scheme.surfaceContainer;

const _tabWidth = 210.0;

/// The "+" after the tabs.
const newTabButtonSize = 32.0;
const _tabHeight = 38.0;

class _TabStrip extends ConsumerWidget {
  const _TabStrip({
    required this.state,
    required this.infoOpen,
    required this.onToggleInfo,
  });

  final SessionsState state;
  final bool infoOpen;
  final VoidCallback onToggleInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Empty space in the tab strip doubles as the title bar.
    return WindowDragArea(
      child: ColoredBox(
        key: const ValueKey('tab-strip'),
        color: tabStripColor(Theme.of(context).colorScheme),
        child: SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _tabs(ref)),
              Padding(
                // Windows: room for the caption buttons at the top right.
                padding: EdgeInsets.fromLTRB(4, 0, 8 + captionButtonsInset, 4),
                child: IconButton(
                  tooltip: infoOpen
                      ? context.l10n.hideInfoPanel
                      : context.l10n.showInfoPanel,
                  isSelected: infoOpen,
                  icon: const Icon(Icons.view_sidebar_outlined),
                  selectedIcon: const Icon(Icons.view_sidebar),
                  onPressed: onToggleInfo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(WidgetRef ref) {
    final sessions = state.sessions;
    return SizedBox(
      height: _tabHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // Start past the terminal card's rounded corner (12 margin + 16
        // radius) plus the selected tab's curved foot, so the foot meets
        // the card's straight top edge.
        padding: const EdgeInsets.symmetric(
          horizontal: 12 + terminalCardRadius + BrowserTabPainter.foot,
        ),
        clipBehavior: Clip.none,
        // Tabs, then the "+" right after the last one (as in browsers).
        itemCount: sessions.length + 1,
        itemBuilder: (context, i) {
          if (i == sessions.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Center(
                // Builder: the picker anchors to this button's own box.
                child: Builder(
                  builder: (buttonContext) => IconButton(
                    key: const ValueKey('new-tab'),
                    tooltip: context.l10n.newSession,
                    // Fixed square so the highlight is a circle around the
                    // icon (the default 48px button got squashed to fit
                    // the tab row and looked off-centre).
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(newTabButtonSize),
                      minimumSize: const Size.square(newTabButtonSize),
                      padding: EdgeInsets.zero,
                      // No extra 48px touch area around it either.
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    iconSize: 20,
                    icon: const Icon(Icons.add),
                    onPressed: () => openHostPicker(buttonContext, ref),
                  ),
                ),
              ),
            );
          }
          final s = sessions[i];
          final selected = s.id == state.activeId;
          final nextSelected =
              i + 1 < sessions.length && sessions[i + 1].id == state.activeId;
          return BrowserTab(
            key: ValueKey('tab-${s.id}'),
            session: s,
            selected: selected,
            // Thin separator between two unselected tabs, as in browsers.
            showDivider: !selected && !nextSelected && i + 1 < sessions.length,
            onTap: () => ref.read(sessionsProvider.notifier).activate(s.id),
            onClose: () => requestCloseSession(context, ref, s),
          );
        },
      ),
    );
  }
}

/// One tab, drawn like a browser tab: the selected one has rounded top
/// corners and curves out at the bottom into the page below (same colour),
/// the others are flat with a soft highlight on hover.
class BrowserTab extends StatefulWidget {
  const BrowserTab({
    super.key,
    required this.session,
    required this.selected,
    required this.showDivider,
    required this.onTap,
    required this.onClose,
  });

  final TerminalSession session;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final fg = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    // Same colour as the terminal window below, so the tab and the window
    // read as one piece.
    final tabColor = terminalThemeFor(scheme).background;
    final hoverColor = scheme.onSurface.withValues(alpha: 0.06);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: _tabWidth,
          height: _tabHeight,
          child: CustomPaint(
            painter: BrowserTabPainter(
              fill: selected ? tabColor : null,
              hover: !selected && _hover ? hoverColor : null,
              divider: widget.showDivider && !_hover
                  ? scheme.outlineVariant
                  : null,
            ),
            child: ListenableBuilder(
              listenable: widget.session,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  children: [
                    _StatusDot(status: widget.session.status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.session.host.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.close,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      color: fg,
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the browser-style tab background.
class BrowserTabPainter extends CustomPainter {
  const BrowserTabPainter({this.fill, this.hover, this.divider});

  /// Selected tab colour (null = not selected).
  final Color? fill;

  /// Hover highlight for an unselected tab.
  final Color? hover;

  /// Separator on the right edge.
  final Color? divider;

  static const radius = 10.0; // top corners
  static const foot = 8.0; // outward curves at the bottom

  /// The selected tab's outline: rounded top, and bottom corners that
  /// curve outwards (extending [foot] past each side) into the page.
  static Path tabPath(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(-foot, h)
      ..arcToPoint(
        Offset(0, h - foot),
        radius: const Radius.circular(foot),
        clockwise: false,
      )
      ..lineTo(0, radius)
      ..arcToPoint(
        const Offset(radius, 0),
        radius: const Radius.circular(radius),
      )
      ..lineTo(w - radius, 0)
      ..arcToPoint(Offset(w, radius), radius: const Radius.circular(radius))
      ..lineTo(w, h - foot)
      ..arcToPoint(
        Offset(w + foot, h),
        radius: const Radius.circular(foot),
        clockwise: false,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fill != null) {
      canvas.drawPath(tabPath(size), Paint()..color = fill!);
      return;
    }
    if (hover != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(2, 3, size.width - 2, size.height - 3),
          const Radius.circular(8),
        ),
        Paint()..color = hover!,
      );
    }
    if (divider != null) {
      final x = size.width - 0.5;
      canvas.drawLine(
        Offset(x, size.height * 0.28),
        Offset(x, size.height * 0.72),
        Paint()
          ..color = divider!
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(BrowserTabPainter old) =>
      old.fill != fill || old.hover != hover || old.divider != divider;
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status == SessionStatus.connecting) {
      return Tooltip(
        message: context.l10n.statusConnecting,
        child: const ShapeMorphIndicator(size: 14),
      );
    }
    final (color, label) = switch (status) {
      SessionStatus.connecting => (
        scheme.tertiary,
        context.l10n.statusConnecting,
      ),
      SessionStatus.connected => (
        Colors.green.shade500,
        context.l10n.statusConnected,
      ),
      SessionStatus.failed => (scheme.error, context.l10n.statusFailed),
      SessionStatus.closed => (scheme.outline, context.l10n.statusClosed),
    };
    return Tooltip(
      message: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Copy / paste shortcuts. Windows uses Ctrl+Shift so plain Ctrl+C, Ctrl+V
/// and Ctrl+A still reach the shell.
/// Shows the host list under the widget at [context] (e.g. the "+"
/// button) and opens a new session for the chosen host.
Future<void> openHostPicker(BuildContext context, WidgetRef ref) async {
  final box = context.findRenderObject() as RenderBox?;
  final anchor = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final host = await showHostPicker(context, anchor: anchor);
  if (host != null) ref.read(sessionsProvider.notifier).open(host);
}

/// Close the current terminal tab: ⌘W on macOS, Ctrl+W elsewhere.
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

SingleActivator get closeTabActivator =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? const SingleActivator(LogicalKeyboardKey.keyW, meta: true)
    : const SingleActivator(LogicalKeyboardKey.keyW, control: true);

/// Go to terminal tab [number] (1-based): ⌘1–⌘9 on macOS, Ctrl+1–Ctrl+9
/// elsewhere. 9 always means the last tab, as in browsers.
class SwitchTabIntent extends Intent {
  const SwitchTabIntent(this.number);

  final int number;
}

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

Map<ShortcutActivator, Intent> get switchTabShortcuts {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  return {
    for (var i = 0; i < _digitKeys.length; i++)
      SingleActivator(_digitKeys[i], meta: mac, control: !mac): SwitchTabIntent(
        i + 1,
      ),
  };
}

/// Activates tab [number] (1-based; 9 = last). Does nothing if there is
/// no such tab.
void switchToTab(WidgetRef ref, int number) {
  final sessions = ref.read(sessionsProvider).sessions;
  if (sessions.isEmpty) return;
  final index = number == 9 ? sessions.length - 1 : number - 1;
  if (index >= sessions.length) return;
  ref.read(sessionsProvider.notifier).activate(sessions[index].id);
}

/// Closes [session]'s tab, asking first while it is connected or
/// connecting. Tabs whose connection already failed or ended close
/// straight away: there is nothing left to lose.
Future<void> requestCloseSession(
  BuildContext context,
  WidgetRef ref,
  TerminalSession session,
) async {
  // A dialog (e.g. this confirmation, after a second ⌘W) is already on
  // top of the page: don't stack another one.
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  final live =
      session.status == SessionStatus.connected ||
      session.status == SessionStatus.connecting;
  if (live) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.tab_unselected),
        title: Text(context.l10n.closeTabTitle),
        content: Text(context.l10n.closeTabBody(session.host.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            autofocus: true, // Enter confirms, Esc cancels
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  ref.read(sessionsProvider.notifier).close(session.id);
}

Map<ShortcutActivator, Intent> get _terminalShortcuts {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return {
      closeTabActivator: const CloseTabIntent(),
      ...switchTabShortcuts,
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
          CopySelectionTextIntent.copy,
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
          const PasteTextIntent(SelectionChangedCause.keyboard),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
    };
  }
  return {
    // Takes Ctrl+W from the shell (where it deletes a word), as asked.
    closeTabActivator: const CloseTabIntent(),
    ...switchTabShortcuts,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
        CopySelectionTextIntent.copy,
    const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
        const PasteTextIntent(SelectionChangedCause.keyboard),
  };
}

/// Corner radius of the terminal card and the info panel.
const terminalCardRadius = 16.0;

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.session,
    required this.isActive,
  });

  final TerminalSession session;
  final bool isActive;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _focusSoon();
  }

  @override
  void didUpdateWidget(TerminalPane old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _focusSoon();
  }

  void _focusSoon() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => mounted ? _focusNode.requestFocus() : null,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _showContextMenu(TapDownDetails details) async {
    final controller = widget.session.controller;
    final selection = controller.selection;
    final position = details.globalPosition;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          enabled: selection != null,
          child: Text(context.l10n.copy),
        ),
        PopupMenuItem(value: 'paste', child: Text(context.l10n.paste)),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        if (selection != null) {
          final text = widget.session.terminal.buffer.getText(selection);
          await Clipboard.setData(ClipboardData(text: text));
          controller.clearSelection();
        }
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          widget.session.terminal.paste(text);
        }
    }
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final terminalTheme = terminalThemeFor(scheme);
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
        // Terminal window as a rounded card.
        child: ClipRRect(
          key: const ValueKey('terminal-card'),
          borderRadius: BorderRadius.circular(terminalCardRadius),
          child: ColoredBox(
            color: terminalTheme.background,
            child: _buildCard(context, session, terminalTheme),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    TerminalSession session,
    TerminalTheme terminalTheme,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.status == SessionStatus.failed ||
            session.status == SessionStatus.closed)
          MaterialBanner(
            backgroundColor: session.status == SessionStatus.failed
                ? scheme.errorContainer
                : scheme.surfaceContainerHigh,
            leading: Icon(
              session.status == SessionStatus.failed
                  ? Icons.error_outline
                  : Icons.link_off,
            ),
            content: Text(session.error ?? context.l10n.connectionClosed),
            actions: [
              TextButton(
                onPressed: session.connect,
                child: Text(context.l10n.reconnect),
              ),
            ],
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TerminalView(
                session.terminal,
                controller: session.controller,
                focusNode: _focusNode,
                theme: terminalTheme,
                textStyle: terminalTextStyle(),
                padding: const EdgeInsets.all(8),
                shortcuts: _terminalShortcuts,
                keyboardAppearance: scheme.brightness,
                onSecondaryTapDown: (details, _) => _showContextMenu(details),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: session.status == SessionStatus.connecting
                    ? _ConnectingOverlay(
                        target: session.host.target,
                        background: terminalTheme.background,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Covers the terminal while the connection is being set up.
class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay({required this.target, required this.background});

  final String target;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ShapeMorphIndicator(size: 64),
            const SizedBox(height: 20),
            Text(
              context.l10n.statusConnecting,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              target,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
