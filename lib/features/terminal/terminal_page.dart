import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/fade_through_stack.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/window_drag_area.dart';
import '../../widgets/shape_morph_indicator.dart';
import '../settings/settings_providers.dart';
import 'info_panel.dart';
import 'sessions_providers.dart';
import 'terminal_session.dart';

class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key, required this.isVisible});

  /// Whether this page is the current navigation destination; used to give
  /// keyboard focus to the active terminal.
  final bool isVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    if (state.sessions.isEmpty) {
      return const PageScaffold(
        title: '终端',
        child: EmptyState(
          icon: Icons.terminal,
          title: '没有打开的会话',
          message: '在“主机”里点一台服务器即可连接',
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
      shortcuts: {closeTabActivator: const CloseTabIntent()},
      child: Actions(
        actions: {
          CloseTabIntent: CallbackAction<CloseTabIntent>(
            onInvoke: (_) {
              closeActive();
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
            child: Row(
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
                  child: TerminalInfoPanel(
                    key: ValueKey('info-${active.id}'),
                    session: active,
                    onClose: () => setInfo(false),
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

/// Slides its child in from the right edge; the terminal beside it
/// shrinks to make room rather than being covered.
class _SlidingPanel extends StatelessWidget {
  const _SlidingPanel({required this.open, required this.child});

  final bool open;
  final Widget child;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? 1 : 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        if (t == 0) return const SizedBox.shrink();
        return SizedBox(
          width: (infoPanelWidth + _gap) * t,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: infoPanelWidth + _gap,
              maxWidth: infoPanelWidth + _gap,
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, _gap, _gap),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(terminalCardRadius),
          child: child,
        ),
      ),
    );
  }
}

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
    // Empty space in the tab strip doubles as the title bar on macOS.
    return WindowDragArea(
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: _tabs(ref)),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: infoOpen ? '隐藏信息栏' : '显示信息栏',
                isSelected: infoOpen,
                icon: const Icon(Icons.view_sidebar_outlined),
                selectedIcon: const Icon(Icons.view_sidebar),
                onPressed: onToggleInfo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.sessions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final s = state.sessions[i];
          return _SessionTab(
            session: s,
            selected: s.id == state.activeId,
            onTap: () => ref.read(sessionsProvider.notifier).activate(s.id),
            onClose: () => requestCloseSession(context, ref, s),
          );
        },
      ),
    );
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final TerminalSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final fg = selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;
        return Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusDot(status: session.status),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      session.host.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: fg),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    color: fg,
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (status == SessionStatus.connecting) {
      return const Tooltip(
        message: '正在连接',
        child: ShapeMorphIndicator(size: 14),
      );
    }
    final (color, label) = switch (status) {
      SessionStatus.connecting => (scheme.tertiary, '正在连接'),
      SessionStatus.connected => (Colors.green.shade500, '已连接'),
      SessionStatus.failed => (scheme.error, '连接失败'),
      SessionStatus.closed => (scheme.outline, '已断开'),
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
/// Close the current terminal tab: ⌘W on macOS, Ctrl+W elsewhere.
class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

SingleActivator get closeTabActivator =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? const SingleActivator(LogicalKeyboardKey.keyW, meta: true)
    : const SingleActivator(LogicalKeyboardKey.keyW, control: true);

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
        title: const Text('关闭标签页？'),
        content: Text('与 ${session.host.displayName} 的 SSH 连接会断开，终端里的内容不会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            autofocus: true, // Enter confirms, Esc cancels
            onPressed: () => Navigator.pop(context, true),
            child: const Text('关闭'),
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
          child: const Text('复制'),
        ),
        const PopupMenuItem(value: 'paste', child: Text('粘贴')),
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
            content: Text(session.error ?? '连接已关闭'),
            actions: [
              TextButton(onPressed: session.connect, child: const Text('重新连接')),
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
            Text('正在连接', style: theme.textTheme.titleMedium),
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
