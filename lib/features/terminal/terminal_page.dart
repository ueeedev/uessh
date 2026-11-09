import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:xterm2/xterm.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/fade_through_stack.dart';
import '../../widgets/window_drag_area.dart';
import '../../widgets/shape_morph_indicator.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import '../files/files_panel.dart';
import '../files/uploads.dart';
import '../../shell/home_shell.dart';
import 'host_picker.dart';
import '../ai/ai_panel.dart';
import 'info_panel.dart';
import 'sessions_providers.dart';
import 'terminal_session.dart';
import 'workspace_layout.dart';
import 'workspace_view.dart';
import '../../l10n/l10n.dart';

/// The window's content: the tab strip (workbench first, then SSH
/// workspaces) and the shown tab.
class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    // An SSH tab is shown (keyboard focus goes to its terminal).
    final isVisible = !state.homeActive;
    final activeIndex = state.tabs.indexWhere((t) => t.id == state.activeTabId);
    final active = state.active;
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

    // The terminal maps these keys to the same intents itself (so the
    // shell doesn't get them); Shortcuts here cover focus elsewhere on
    // the page.
    return Shortcuts(
      shortcuts: {
        closeTabActivator: const CloseTabIntent(),
        ...switchTabShortcuts,
        ...workspaceShortcuts,
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
              switchToTab(ref, intent.number);
              return null;
            },
          ),
          SplitPaneIntent: CallbackAction<SplitPaneIntent>(
            onInvoke: (intent) {
              final current = ref.read(sessionsProvider).active;
              if (isVisible && current != null) {
                splitPane(context, ref, current, intent.side);
              }
              return null;
            },
          ),
          FocusPaneIntent: CallbackAction<FocusPaneIntent>(
            onInvoke: (intent) {
              if (isVisible) {
                ref
                    .read(sessionsProvider.notifier)
                    .focusNeighbour(intent.direction);
              }
              return null;
            },
          ),
          ZoomPaneIntent: CallbackAction<ZoomPaneIntent>(
            onInvoke: (_) {
              final current = ref.read(sessionsProvider).active;
              if (isVisible && current != null) {
                ref.read(sessionsProvider.notifier).toggleZoom(current.id);
              }
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
          isVisible,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    SessionsState state,
    int activeIndex,
    TerminalSession? active,
    bool infoSetting,
    void Function(bool) setInfo,
    bool isVisible,
  ) {
    final panel = ref.watch(settingsProvider.select((s) => s.terminalPanel));
    final showInfo = infoSetting;
    final showFiles = ref.watch(
      settingsProvider.select((s) => s.showFilePanel),
    );
    void setFiles(bool v) => ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(showFilePanel: v));
    // Same colour as the tab strip, so the rounded terminal cards and the
    // side panel stand out from it in both light and dark themes.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabStrip(state: state),
          Expanded(
            // The workbench, or the SSH tab (kept alive behind it).
            child: FadeThroughIndexedStack(
              duration: const Duration(milliseconds: 200),
              index: isVisible ? 1 : 0,
              children: [
                const _HomeCard(),
                if (active == null)
                  const SizedBox.shrink()
                else
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      // Quicker than page switches: tabs are switched
                                      // often.
                                      child: FadeThroughIndexedStack(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        index: activeIndex < 0
                                            ? 0
                                            : activeIndex,
                                        children: [
                                          for (final t in state.tabs)
                                            WorkspaceView(
                                              key: ValueKey(t.id),
                                              tab: t,
                                              isActive:
                                                  isVisible &&
                                                  t.id == state.activeTabId,
                                              bottomGap: showFiles ? 0 : 12,
                                            ),
                                        ],
                                      ),
                                    ),
                                    _BottomPanel(
                                      open: showFiles,
                                      available: constraints.maxHeight,
                                      height: ref.watch(
                                        settingsProvider.select(
                                          (s) => s.filePanelHeight,
                                        ),
                                      ),
                                      onHeightChanged: (h) => ref
                                          .read(settingsProvider.notifier)
                                          .update(
                                            (s) =>
                                                s.copyWith(filePanelHeight: h),
                                          ),
                                      // Follows the focused pane.
                                      child: FilesPanel(
                                        key: ValueKey('files-${active.id}'),
                                        session: active,
                                        onClose: () => setFiles(false),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Uploads, wherever they were started.
                              const Positioned(
                                right: 20,
                                bottom: 24,
                                child: UploadProgressCard(),
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
                          // Follows the focused pane.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: panel == TerminalPanel.ai
                                ? AiPanel(
                                    key: ValueKey('ai-${active.id}'),
                                    session: active,
                                    onClose: () => setInfo(false),
                                  )
                                : TerminalInfoPanel(
                                    key: ValueKey('info-${active.id}'),
                                    session: active,
                                    onClose: () => setInfo(false),
                                  ),
                          ),
                        ),
                        _SideRail(
                          panelOpen: showInfo,
                          panel: panel,
                          filesOpen: showFiles,
                          onToggleFiles: () => setFiles(!showFiles),
                          onTogglePanel: (p) {
                            // Same button again closes; the other switches over.
                            if (showInfo && panel == p) {
                              setInfo(false);
                            } else {
                              ref
                                  .read(settingsProvider.notifier)
                                  .update(
                                    (s) => s.copyWith(
                                      showTerminalInfo: true,
                                      terminalPanel: p,
                                    ),
                                  );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The workbench tab's content: the workbench in a rounded card the
/// selected tab flows into, like the terminal cards.
class _HomeCard extends StatelessWidget {
  const _HomeCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: ClipRRect(
        key: const ValueKey('home-card'),
        borderRadius: BorderRadius.circular(terminalCardRadius),
        child: ColoredBox(
          color: terminalThemeFor(scheme).background,
          child: const HomeView(),
        ),
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

/// The buttons down the right edge of the terminal page: AI assistant,
/// files, info. Each opens its panel; again closes it.
class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.panelOpen,
    required this.panel,
    required this.filesOpen,
    required this.onTogglePanel,
    required this.onToggleFiles,
  });

  final bool panelOpen;
  final TerminalPanel panel;
  final bool filesOpen;
  final ValueChanged<TerminalPanel> onTogglePanel;
  final VoidCallback onToggleFiles;

  static const width = 48.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final aiOpen = panelOpen && panel == TerminalPanel.ai;
    final infoOpen = panelOpen && panel == TerminalPanel.info;
    final scheme = Theme.of(context).colorScheme;
    Widget button({
      required Key key,
      required String tip,
      required bool selected,
      required Widget icon,
      required Widget selectedIcon,
      required VoidCallback onPressed,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IconButton(
        key: key,
        tooltip: tip,
        isSelected: selected,
        icon: icon,
        selectedIcon: selectedIcon,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.secondaryContainer : null,
          foregroundColor: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        onPressed: onPressed,
      ),
    );
    return SizedBox(
      key: const ValueKey('side-rail'),
      width: width,
      child: Column(
        children: [
          button(
            key: const ValueKey('toggle-ai-panel'),
            tip: aiOpen ? l.aiHidePanel : l.aiShowPanel,
            selected: aiOpen,
            icon: const Icon(Symbols.smart_toy),
            selectedIcon: const Icon(Symbols.smart_toy, fill: 1),
            onPressed: () => onTogglePanel(TerminalPanel.ai),
          ),
          button(
            key: const ValueKey('toggle-files'),
            tip: filesOpen ? l.filesHide : l.filesShow,
            selected: filesOpen,
            icon: const Icon(Icons.folder_outlined),
            selectedIcon: const Icon(Icons.folder),
            onPressed: onToggleFiles,
          ),
          button(
            key: const ValueKey('toggle-info-panel'),
            tip: infoOpen ? l.hideInfoPanel : l.showInfoPanel,
            selected: infoOpen,
            icon: const Icon(Icons.view_sidebar_outlined),
            selectedIcon: const Icon(Icons.view_sidebar),
            onPressed: () => onTogglePanel(TerminalPanel.info),
          ),
        ],
      ),
    );
  }
}

/// The file panel below the terminal: slides up from the bottom (the
/// terminal shrinks), with a handle above it to drag its height
/// (double-click: default height).
class _BottomPanel extends StatefulWidget {
  const _BottomPanel({
    required this.open,
    required this.available,
    required this.height,
    required this.onHeightChanged,
    required this.child,
  });

  final bool open;
  final double available;
  final double height;
  final ValueChanged<double> onHeightChanged;
  final Widget child;

  static const gap = 12.0;

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  double? _dragHeight;
  bool _hover = false;

  double _clamp(double h) {
    final max = (widget.available * 0.7).clamp(
      AppSettings.minFilePanelHeight,
      AppSettings.maxFilePanelHeight,
    );
    return h.clamp(AppSettings.minFilePanelHeight, max);
  }

  @override
  Widget build(BuildContext context) {
    const gap = _BottomPanel.gap;
    final height = _clamp(_dragHeight ?? widget.height);
    final scheme = Theme.of(context).colorScheme;
    final dragging = _dragHeight != null;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.open ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        if (t == 0) return const SizedBox.shrink();
        return SizedBox(
          height: (height + gap * 2) * t,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: height + gap * 2,
              maxHeight: height + gap * 2,
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              key: const ValueKey('files-panel-handle'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: (_) =>
                  setState(() => _dragHeight = widget.height),
              // Dragging up makes the panel taller.
              onVerticalDragUpdate: (d) => setState(
                () => _dragHeight = _clamp(
                  (_dragHeight ?? widget.height) - d.delta.dy,
                ),
              ),
              onVerticalDragEnd: (_) {
                final h = _clamp(_dragHeight ?? widget.height);
                setState(() => _dragHeight = null);
                widget.onHeightChanged(h);
              },
              onDoubleTap: () =>
                  widget.onHeightChanged(AppSettings.defaultFilePanelHeight),
              child: SizedBox(
                height: gap,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hover || dragging ? 1 : 0,
                    child: Container(
                      width: 40,
                      height: 4,
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
          SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(terminalCardRadius),
                child: widget.child,
              ),
            ),
          ),
          const SizedBox(height: gap),
        ],
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
const _tabHeight = 32.0;

/// Height of the tab strip at the top of the window. The macOS window
/// buttons are moved to line up with the tabs (MainFlutterWindow.swift,
/// trafficLightCenterY = 24 = this minus half a tab).
const tabStripHeight = 40.0;

class _TabStrip extends ConsumerStatefulWidget {
  const _TabStrip({required this.state});

  final SessionsState state;

  @override
  ConsumerState<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<_TabStrip> {
  final _scroll = ScrollController();

  /// Where a dragged tab / pane would be inserted (null: not dragging).
  int? _insertAt;

  /// Workspace tab whose name is being edited.
  String? _renamingTabId;

  /// Tab being dragged from this strip (its slot closes up meanwhile).
  String? _draggingTabId;

  final _listKey = GlobalKey();

  /// Hovering a dragged pane over a tab for a moment opens that tab, so
  /// the pane can be dropped into its workspace.
  Timer? _hoverTimer;
  String? _hoverTabId;

  /// Where the tabs start: past the cards' rounded corner (12 margin + 16
  /// radius) plus the selected tab's curved foot, so the foot meets the
  /// card's straight top edge; on macOS also past the window buttons.
  static double get _leftPad => tabStripLeftPad;

  /// Start of the SSH tabs (after the pinned workbench tab).
  static double get _sshStart => _leftPad + homeTabWidth;

  SessionsState get state => widget.state;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Empty space in the tab strip doubles as the title bar. The tab list
    // covers it, so this works on raw pointer events (see _isBlank).
    return TitleBarListener(
      isBlank: _isBlank,
      child: ColoredBox(
        key: const ValueKey('tab-strip'),
        color: tabStripColor(Theme.of(context).colorScheme),
        child: SizedBox(
          height: tabStripHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: KeyedSubtree(key: _listKey, child: _dropArea(context)),
              ),
              // Windows: room for the caption buttons at the top right.
              SizedBox(width: captionButtonsInset),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab slot under global position [global] (0..tabs.length) and the
  /// tab under it, if any.
  double get _scrollOffset => _scroll.hasClients ? _scroll.offset : 0;

  /// Whether [local] (in the strip) is empty strip: not a tab, not the
  /// "+" button, not the buttons on the right.
  bool _isBlank(Offset local) {
    final listWidth = _listKey.currentContext?.size?.width ?? 0;
    if (local.dx >= listWidth) return false; // AI / info buttons
    if (local.dy < tabStripHeight - _tabHeight) return true; // above tabs
    final x = local.dx + _scrollOffset - _leftPad;
    if (x >= 0 && x < homeTabWidth) return false; // the workbench tab
    final end =
        homeTabWidth + state.tabs.length * _tabWidth + 6 + newTabButtonSize;
    return x < 0 || x > end;
  }

  /// Slot under global position [global] and the tab under it, if any.
  /// While a tab of this strip is dragged, slots count the other tabs
  /// only (its own slot has closed up).
  (int, WorkspaceTab?) _slotAt(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return (state.tabs.length, null);
    final x = box.globalToLocal(global).dx - _sshStart + _scrollOffset;
    final pos = x / _tabWidth;
    final count = state.tabs.length - (_draggingTabId == null ? 0 : 1);
    final slot = pos.round().clamp(0, count);
    final under = pos >= 0 && pos < state.tabs.length
        ? state.tabs[pos.floor()]
        : null;
    return (slot, under);
  }

  void _clearDrag() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoverTabId = null;
    if (_insertAt != null) setState(() => _insertAt = null);
  }

  Widget _dropArea(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => d.data is PaneDrag || d.data is TabDrag,
      onMove: (d) {
        final (slot, under) = _slotAt(d.offset);
        if (slot != _insertAt) setState(() => _insertAt = slot);
        // A pane held over another tab opens it after a moment.
        if (d.data is PaneDrag &&
            under != null &&
            under.id != state.activeTabId) {
          if (_hoverTabId != under.id) {
            _hoverTimer?.cancel();
            _hoverTabId = under.id;
            _hoverTimer = Timer(const Duration(milliseconds: 500), () {
              ref.read(sessionsProvider.notifier).activateTab(under.id);
            });
          }
        } else {
          _hoverTimer?.cancel();
          _hoverTabId = null;
        }
      },
      onLeave: (_) => _clearDrag(),
      onAcceptWithDetails: (d) {
        final (slot, _) = _slotAt(d.offset);
        _clearDrag();
        final n = ref.read(sessionsProvider.notifier);
        switch (d.data) {
          case PaneDrag(:final sessionId):
            n.detachToTab(sessionId, index: slot);
          case TabDrag(:final tabId):
            // Slot among the other tabs -> index in the full strip.
            final from = state.tabs.indexWhere((t) => t.id == tabId);
            n.moveTab(tabId, from >= 0 && slot >= from ? slot + 1 : slot);
        }
      },
      builder: (context, candidates, _) =>
          _tabs(gapAt: candidates.isEmpty ? null : _insertAt),
    );
  }

  /// The tab list; [gapAt] opens a tab-wide gap before that slot (counting
  /// tabs other than the dragged one) to show where a drop lands.
  Widget _tabs({int? gapAt}) {
    final tabs = state.tabs;
    final draggedIndex = tabs.indexWhere((t) => t.id == _draggingTabId);
    // Index among the tabs that aren't being dragged.
    int slotOf(int i) => draggedIndex >= 0 && draggedIndex < i ? i - 1 : i;
    Widget withGap(int at, Widget child) => AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(left: gapAt == at ? _tabWidth : 0),
      child: child,
    );
    return SizedBox(
      height: _tabHeight,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(
          left: _leftPad,
          right: 12 + terminalCardRadius + BrowserTabPainter.foot,
        ),
        clipBehavior: Clip.none,
        // The pinned workbench tab, the SSH tabs, then the "+" right after
        // the last one (as in browsers).
        itemCount: tabs.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return HomeTab(
              selected: state.homeActive,
              showDivider:
                  !state.homeActive &&
                  (tabs.isEmpty || tabs.first.id != state.activeTabId),
              onTap: () => ref.read(sessionsProvider.notifier).showHome(),
            );
          }
          final i = index - 1;
          if (i == tabs.length) {
            return withGap(
              slotOf(i),
              Padding(
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
              ),
            );
          }
          final t = tabs[i];
          final dragged = t.id == _draggingTabId;
          final mySlot = dragged ? -1 : slotOf(i);
          final s = state.session(t.focusedId);
          if (s == null) return const SizedBox(width: _tabWidth);
          final selected = !state.homeActive && t.id == state.activeTabId;
          final nextSelected =
              !state.homeActive &&
              i + 1 < tabs.length &&
              tabs[i + 1].id == state.activeTabId;
          final renaming = _renamingTabId == t.id && t.isSplit;
          final tab = BrowserTab(
            key: ValueKey('tab-${t.id}'),
            session: s,
            paneCount: t.paneIds.length,
            title: t.isSplit
                ? (t.name ?? context.l10n.workspaceName(t.number ?? 1))
                : null,
            renaming: renaming,
            onRenameDone: (name) {
              setState(() => _renamingTabId = null);
              if (name != null) {
                ref.read(sessionsProvider.notifier).rename(t.id, name);
              }
            },
            selected: selected,
            // Thin separator between two unselected tabs, as in browsers.
            showDivider: !selected && !nextSelected && i + 1 < tabs.length,
            // Clicking the current workspace tab renames it.
            onTap: () {
              if (selected && t.isSplit) {
                setState(() => _renamingTabId = t.id);
              } else {
                ref.read(sessionsProvider.notifier).activateTab(t.id);
              }
            },
            onClose: () => t.isSplit
                ? requestCloseTab(context, ref, t)
                : requestCloseSession(context, ref, s),
          );
          return withGap(
            mySlot,
            Draggable<Object>(
              data: TabDrag(t.id),
              // No dragging while its name is being typed.
              maxSimultaneousDrags: renaming ? 0 : null,
              onDragStarted: () => setState(() => _draggingTabId = t.id),
              onDragEnd: (_) => setState(() => _draggingTabId = null),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: DragChip(
                label: t.isSplit
                    ? (t.name ?? context.l10n.workspaceName(t.number ?? 1))
                    : s.host.displayName,
                count: t.paneIds.length,
              ),
              // Its slot closes up; the gap shows where it will land.
              childWhenDragging: const SizedBox.shrink(),
              child: tab,
            ),
          );
        },
      ),
    );
  }
}

/// Where the tabs start: past the cards' rounded corner (12 margin + 16
/// radius) plus the selected tab's curved foot, so the foot meets the
/// card's straight top edge; on macOS also past the window buttons.
double get tabStripLeftPad => defaultTargetPlatform == TargetPlatform.macOS
    ? 84
    : 12 + terminalCardRadius + BrowserTabPainter.foot;

/// The line after the workbench tab continues the workbench sidebar's
/// right edge below it (card margin + sidebar width).
const _sidebarEdge = 12 + sideNavWidth;

/// Gap between that line and the first SSH tab (room for its curved foot).
const _afterHomeGap = BrowserTabPainter.foot + 4;

/// The workbench tab's slot: from the start of the strip to the line,
/// plus the gap after it.
double get homeTabWidth => _sidebarEdge - tabStripLeftPad + _afterHomeGap;

/// The pinned first tab: the workbench (home). Not draggable, no close.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    // Its own look - a pill, not a browser tab: the workbench isn't one
    // of the SSH tabs.
    return SizedBox(
      width: homeTabWidth,
      height: _tabHeight,
      child: Row(
        children: [
          Expanded(
            // From the start of the strip (right after the macOS window
            // buttons); the line sits at the sidebar's edge.
            child: Align(
              alignment: Alignment.centerLeft,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  key: const ValueKey('home-tab'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.secondaryContainer
                          : _hover
                          ? scheme.onSurface.withValues(alpha: 0.06)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected
                              ? Icons.space_dashboard
                              : Icons.space_dashboard_outlined,
                          size: 17,
                          color: fg,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            context.l10n.workbench,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: fg,
                              fontWeight: selected ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Sets it apart from the SSH tabs, in line with the sidebar's
          // edge below.
          Container(
            key: const ValueKey('home-tab-divider'),
            width: 1,
            height: 18,
            color: scheme.outlineVariant,
          ),
          const SizedBox(width: _afterHomeGap - 1),
        ],
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
    this.paneCount = 1,
    this.title,
    this.renaming = false,
    this.onRenameDone,
  });

  /// The tab's focused pane (its status, and its name for a single pane).
  final TerminalSession session;

  /// Panes in the tab's workspace; more than one shows a count badge.
  final int paneCount;

  /// Workspace name, shown instead of the host for split tabs.
  final String? title;

  /// Shows a text field to rename the workspace.
  final bool renaming;

  /// The new name, or null when renaming was cancelled (Esc).
  final ValueChanged<String?>? onRenameDone;
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
                    if (widget.title != null)
                      Icon(Icons.dashboard_outlined, size: 15, color: fg)
                    else
                      SessionStatusDot(status: widget.session.status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: widget.renaming
                          ? _RenameField(
                              initial: widget.title ?? '',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                              onDone: (v) => widget.onRenameDone?.call(v),
                            )
                          : Tooltip(
                              message: widget.title != null && selected
                                  ? context.l10n.renameWorkspaceHint
                                  : '',
                              waitDuration: const Duration(milliseconds: 600),
                              child: Text(
                                widget.title ?? widget.session.host.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: fg,
                                  fontWeight: selected ? FontWeight.w600 : null,
                                ),
                              ),
                            ),
                    ),
                    if (widget.paneCount > 1)
                      Container(
                        key: const ValueKey('tab-pane-count'),
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.paneCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
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

/// Inline editor for a workspace name: Enter or clicking away saves,
/// Esc cancels.
class _RenameField extends StatefulWidget {
  const _RenameField({
    required this.initial,
    required this.style,
    required this.onDone,
  });

  final String initial;
  final TextStyle? style;
  final ValueChanged<String?> onDone;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_controller.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish(String? value) {
    if (_done) return;
    _done = true;
    widget.onDone(value);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        key: const ValueKey('rename-workspace'),
        controller: _controller,
        focusNode: _focus,
        style: widget.style,
        maxLength: 40,
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
        onSubmitted: _finish,
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

class SessionStatusDot extends StatelessWidget {
  const SessionStatusDot({super.key, required this.status});

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
  final n = ref.read(sessionsProvider.notifier);
  final tabs = ref.read(sessionsProvider).tabs;
  // 1 is the workbench; SSH tabs follow. 9 is the last tab.
  if (number == 1 || (number == 9 && tabs.isEmpty)) {
    n.showHome();
    return;
  }
  final index = number == 9 ? tabs.length - 1 : number - 2;
  if (index < 0 || index >= tabs.length) return;
  n.activateTab(tabs[index].id);
}

/// Split the focused pane: ⌘D / ⌘⇧D on macOS, Ctrl+Shift+D / Ctrl+Shift+E
/// elsewhere (plain Ctrl+D belongs to the shell).
class SplitPaneIntent extends Intent {
  const SplitPaneIntent(this.side);
  final DropSide side;
}

/// Move focus to the pane in [direction]: ⌘⌥ + arrow on macOS, Alt +
/// arrow elsewhere.
class FocusPaneIntent extends Intent {
  const FocusPaneIntent(this.direction);
  final PaneDirection direction;
}

/// Maximize / restore the focused pane: ⌘⇧Enter, Ctrl+Shift+Enter.
class ZoomPaneIntent extends Intent {
  const ZoomPaneIntent();
}

Map<ShortcutActivator, Intent> get workspaceShortcuts {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  SingleActivator focus(LogicalKeyboardKey key) => mac
      ? SingleActivator(key, meta: true, alt: true)
      : SingleActivator(key, alt: true);
  return {
    if (mac) ...{
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
          const SplitPaneIntent(DropSide.right),
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
          const SplitPaneIntent(DropSide.bottom),
      const SingleActivator(LogicalKeyboardKey.enter, meta: true, shift: true):
          const ZoomPaneIntent(),
    } else ...{
      const SingleActivator(
        LogicalKeyboardKey.keyD,
        control: true,
        shift: true,
      ): const SplitPaneIntent(
        DropSide.right,
      ),
      const SingleActivator(
        LogicalKeyboardKey.keyE,
        control: true,
        shift: true,
      ): const SplitPaneIntent(
        DropSide.bottom,
      ),
      const SingleActivator(
        LogicalKeyboardKey.enter,
        control: true,
        shift: true,
      ): const ZoomPaneIntent(),
    },
    focus(LogicalKeyboardKey.arrowLeft): const FocusPaneIntent(
      PaneDirection.left,
    ),
    focus(LogicalKeyboardKey.arrowRight): const FocusPaneIntent(
      PaneDirection.right,
    ),
    focus(LogicalKeyboardKey.arrowUp): const FocusPaneIntent(PaneDirection.up),
    focus(LogicalKeyboardKey.arrowDown): const FocusPaneIntent(
      PaneDirection.down,
    ),
  };
}

/// Closes a split tab (all its panes), asking first if any is live.
Future<void> requestCloseTab(
  BuildContext context,
  WidgetRef ref,
  WorkspaceTab tab,
) async {
  if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
  final state = ref.read(sessionsProvider);
  final live = tab.paneIds
      .map(state.session)
      .where(
        (s) =>
            s != null &&
            (s.status == SessionStatus.connected ||
                s.status == SessionStatus.connecting),
      )
      .length;
  if (live > 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.dashboard_outlined),
        title: Text(context.l10n.closeWorkspaceTitle),
        content: Text(context.l10n.closeWorkspaceBody(live)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  ref.read(sessionsProvider.notifier).closeTab(tab.id);
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
      ...workspaceShortcuts,
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
    ...workspaceShortcuts,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
        CopySelectionTextIntent.copy,
    const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
        const PasteTextIntent(SelectionChangedCause.keyboard),
  };
}

/// Corner radius of the terminal card and the info panel.
const terminalCardRadius = 16.0;

class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({
    super.key,
    required this.session,
    required this.isActive,
  });

  final TerminalSession session;
  final bool isActive;

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
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
    final l = context.l10n;
    final controller = widget.session.controller;
    final selection = controller.selection;
    final position = details.globalPosition;
    final tab = ref.read(sessionsProvider).tabOf(widget.session.id);
    final split = tab?.isSplit ?? false;
    final zoomed = tab?.zoomedId == widget.session.id;
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
          child: Text(l.copy),
        ),
        PopupMenuItem(value: 'paste', child: Text(l.paste)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'split-right', child: Text(l.splitRight)),
        PopupMenuItem(value: 'split-down', child: Text(l.splitDown)),
        if (split) ...[
          PopupMenuItem(
            value: 'zoom',
            child: Text(zoomed ? l.restorePane : l.zoomPane),
          ),
          PopupMenuItem(
            value: 'broadcast',
            child: Text(tab!.broadcast ? l.broadcastOff : l.broadcastOn),
          ),
          PopupMenuItem(value: 'detach', child: Text(l.moveToNewTab)),
          PopupMenuItem(value: 'close', child: Text(l.closePane)),
        ],
      ],
    );
    if (!mounted) return;
    final n = ref.read(sessionsProvider.notifier);
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
      case 'split-right':
        await splitPane(context, ref, widget.session, DropSide.right);
        return;
      case 'split-down':
        await splitPane(context, ref, widget.session, DropSide.bottom);
        return;
      case 'zoom':
        n.toggleZoom(widget.session.id);
      case 'broadcast':
        if (tab != null) n.toggleBroadcast(tab.id);
      case 'detach':
        n.detachToTab(widget.session.id);
      case 'close':
        await requestCloseSession(context, ref, widget.session);
        return;
    }
    if (mounted) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final terminalTheme = terminalThemeFor(Theme.of(context).colorScheme);
    final session = widget.session;
    // The card (rounded corners, padding) comes from WorkspacePane.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _buildCard(context, session, terminalTheme),
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
        if (session.reconnectPending ||
            (session.status == SessionStatus.connecting &&
                session.reconnectAttempt > 0))
          _ReconnectBanner(session: session)
        else if (session.status == SessionStatus.failed ||
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

/// Shown while an automatic reconnect waits (with a countdown) or runs.
class _ReconnectBanner extends StatefulWidget {
  const _ReconnectBanner({required this.session});

  final TerminalSession session;

  @override
  State<_ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<_ReconnectBanner> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Updates the countdown.
    _tick = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final at = s.reconnectAt;
    final waiting = s.reconnectPending && at != null;
    final left = waiting
        ? (at.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(
            0,
            1 << 20,
          )
        : 0;
    return MaterialBanner(
      key: const ValueKey('reconnect-banner'),
      backgroundColor: scheme.surfaceContainerHigh,
      leading: waiting
          ? const Icon(Icons.sync)
          : const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
      content: Text(
        waiting
            ? l.reconnectBanner(left, s.reconnectAttempt, s.reconnectTotal)
            : l.reconnectingNow(s.reconnectAttempt, s.reconnectTotal),
      ),
      actions: [
        if (waiting)
          TextButton(
            key: const ValueKey('reconnect-now'),
            onPressed: () => s.connect(auto: true),
            child: Text(l.reconnectNow),
          ),
        TextButton(
          key: const ValueKey('reconnect-cancel'),
          onPressed: waiting ? s.cancelReconnect : s.close,
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
