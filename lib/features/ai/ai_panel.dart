import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../l10n/l10n.dart';
import '../../shell/navigation.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/shape_morph_indicator.dart';
import '../terminal/terminal_session.dart';
import 'ai_chat.dart';
import 'command_safety.dart';
import 'markdown_view.dart';
import 'ai_config.dart';
import 'ai_history.dart';
import '../hosts/host_overview.dart' show formatTimeAgo;

/// Chat with an AI model about the terminal tab [session], beside the
/// terminal. Each tab keeps its own conversation.
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key, required this.session, required this.onClose});

  final TerminalSession session;
  final VoidCallback onClose;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  /// Showing the list of saved conversations instead of the chat.
  bool _showHistory = false;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// The model to use: the last picked, if its provider still has a key;
  /// otherwise the first model of the first ready provider.
  AiModelRef? _model(AiConfig config) {
    final sel = config.selected;
    if (sel != null && config.configured.contains(sel.providerId)) return sel;
    for (final p in config.ready) {
      final models = ref.watch(aiModelsProvider(p.id)).value;
      if (models != null && models.isNotEmpty) {
        return (providerId: p.id, model: models.first);
      }
    }
    return null;
  }

  void _send(AiModelRef? model, [String? text]) {
    final message = text ?? _input.text;
    if (model == null || message.trim().isEmpty) return;
    ref
        .read(aiChatProvider(widget.session.id).notifier)
        .send(message, model: model, session: widget.session);
    if (text == null) _input.clear();
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final config = ref.watch(aiConfigProvider);
    final chat = ref.watch(aiChatProvider(widget.session.id));
    ref.listen(aiChatProvider(widget.session.id), (prev, next) {
      // Follow the reply while it streams, unless the user scrolled up.
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels < 80) _scrollToEnd();
    });

    final value = config.value;
    final Widget body;
    AiModelRef? model;
    if (value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (value.ready.isEmpty) {
      body = const _SetupHint();
    } else if (_showHistory) {
      model = _model(value);
      body = _HistoryList(
        hostId: widget.session.host.id,
        currentId: ref
            .read(aiChatProvider(widget.session.id).notifier)
            .conversationId,
        onOpen: (id) async {
          final ok = await ref
              .read(aiChatProvider(widget.session.id).notifier)
              .open(id);
          if (!mounted) return;
          setState(() => _showHistory = false);
          if (ok) _scrollToEnd();
        },
      );
    } else {
      model = _model(value);
      body = chat.messages.isEmpty
          // A new chat starts empty: no greeting, no suggestions.
          ? const SizedBox.expand(key: ValueKey('ai-empty'))
          : ListView.builder(
              key: const ValueKey('ai-messages'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: chat.messages.length,
              itemBuilder: (context, i) => _MessageView(
                message: chat.messages[i],
                session: widget.session,
                // One model label per reply, not per tool round.
                showModel: i == 0 || chat.messages[i - 1].fromUser,
                onApprove: ref
                    .read(aiChatProvider(widget.session.id).notifier)
                    .approve,
                onDeny: ref
                    .read(aiChatProvider(widget.session.id).notifier)
                    .deny,
              ),
            );
    }

    return Material(
      key: const ValueKey('ai-panel'),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Icon(
                  Symbols.smart_toy,
                  fill: 1,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showHistory ? l.aiHistory : l.aiAssistant,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('ai-history'),
                  tooltip: _showHistory ? l.aiBackToChat : l.aiHistory,
                  isSelected: _showHistory,
                  icon: const Icon(Icons.history),
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                ),
                if (chat.messages.isNotEmpty && !_showHistory)
                  IconButton(
                    key: const ValueKey('ai-new-chat'),
                    tooltip: l.aiNewChat,
                    icon: const Icon(Icons.add_comment_outlined),
                    onPressed: () => ref
                        .read(aiChatProvider(widget.session.id).notifier)
                        .clear(),
                  ),
                IconButton(
                  tooltip: l.aiClosePanel,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          // "Allow all" is on: say so, always.
          if (value?.toolMode == AiToolMode.allowAll)
            Material(
              key: const ValueKey('ai-allow-all-banner'),
              color: theme.colorScheme.errorContainer,
              child: InkWell(
                onTap: () => ref
                    .read(navigationProvider.notifier)
                    .go(AppDestination.settings),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.aiAllowAllActive,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(_showHistory), child: body),
            ),
          ),
          if (value != null && value.ready.isNotEmpty && !_showHistory)
            _Composer(
              controller: _input,
              focusNode: _inputFocus,
              config: value,
              model: model,
              chat: chat,
              onSend: () => _send(model),
              onStop: () =>
                  ref.read(aiChatProvider(widget.session.id).notifier).stop(),
              onAttach: (on) => ref
                  .read(aiChatProvider(widget.session.id).notifier)
                  .setAttachTerminal(on),
              onPick: (m) => ref.read(aiConfigProvider.notifier).select(m),
            ),
        ],
      ),
    );
  }
}

/// Saved conversations, this host's first. Tap to open (and continue),
/// or delete.
class _HistoryList extends ConsumerWidget {
  const _HistoryList({
    required this.hostId,
    required this.currentId,
    required this.onOpen,
  });

  final String hostId;
  final String? currentId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final history = ref.watch(aiHistoryProvider);
    final all = history.value;
    if (all == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 40, color: scheme.outline),
            const SizedBox(height: 8),
            Text(
              l.aiHistoryEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final mine = [
      for (final c in all)
        if (c.hostId == hostId) c,
    ];
    final others = [
      for (final c in all)
        if (c.hostId != hostId) c,
    ];

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
      ),
    );

    Widget tile(AiConversationInfo c) {
      final current = c.id == currentId;
      return ListTile(
        key: ValueKey('ai-history-${c.id}'),
        dense: true,
        selected: current,
        selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.only(left: 20, right: 8),
        title: Text(
          c.title.isEmpty ? '…' : c.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (c.hostId != hostId) c.hostName,
            ?c.model,
            formatTimeAgo(l, c.updatedAt),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          key: ValueKey('ai-history-delete-${c.id}'),
          tooltip: l.aiHistoryDelete,
          iconSize: 18,
          icon: const Icon(Icons.delete_outline),
          onPressed: () => ref.read(aiHistoryProvider.notifier).delete(c.id),
        ),
        onTap: () => onOpen(c.id),
      );
    }

    return ListView(
      key: const ValueKey('ai-history-list'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (mine.isNotEmpty) ...[
          header(l.aiHistoryThisHost),
          for (final c in mine) tile(c),
        ],
        if (others.isNotEmpty) ...[
          header(l.aiHistoryOtherHosts),
          for (final c in others) tile(c),
        ],
      ],
    );
  }
}

class _SetupHint extends ConsumerWidget {
  const _SetupHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              l.aiSetupTitle,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              l.aiSetupBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('ai-open-settings'),
              onPressed: () => ref
                  .read(navigationProvider.notifier)
                  .go(AppDestination.settings),
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.aiOpenSettings),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.config,
    required this.model,
    required this.chat,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onPick,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final AiConfig config;
  final AiModelRef? model;
  final AiChatState chat;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<bool> onAttach;
  final ValueChanged<AiModelRef> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                // Enter sends; Shift+Enter (and Enter while an input method
                // is composing) types a new line as usual.
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed &&
                      !controller.value.composing.isValid) {
                    if (!chat.busy) onSend();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const ValueKey('ai-input'),
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  // Same size as the hint.
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    hintText: l.aiInputHint,
                    hintStyle: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    hintMaxLines: 1,
                    border: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _ModelPicker(
                        config: config,
                        model: model,
                        onPick: onPick,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('ai-attach-terminal'),
                    tooltip: chat.attachTerminal ? l.aiAttachOn : l.aiAttachOff,
                    isSelected: chat.attachTerminal,
                    icon: const Icon(Icons.terminal),
                    selectedIcon: const Icon(Icons.terminal),
                    style: IconButton.styleFrom(
                      backgroundColor: chat.attachTerminal
                          ? scheme.secondaryContainer
                          : null,
                      foregroundColor: chat.attachTerminal
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: () => onAttach(!chat.attachTerminal),
                  ),
                  const SizedBox(width: 4),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => chat.busy
                        ? IconButton.filledTonal(
                            key: const ValueKey('ai-stop'),
                            tooltip: l.aiStop,
                            icon: const Icon(Icons.stop),
                            onPressed: onStop,
                          )
                        : IconButton.filled(
                            key: const ValueKey('ai-send'),
                            tooltip: l.aiSend,
                            icon: const Icon(Icons.arrow_upward),
                            onPressed:
                                model == null || controller.text.trim().isEmpty
                                ? null
                                : onSend,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button showing the current model; opens a menu of models by provider.
class _ModelPicker extends ConsumerWidget {
  const _ModelPicker({
    required this.config,
    required this.model,
    required this.onPick,
  });

  final AiConfig config;
  final AiModelRef? model;
  final ValueChanged<AiModelRef> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        for (final p in config.ready)
          SubmenuButton(
            key: ValueKey('ai-provider-${p.id}'),
            menuChildren: [
              _ModelItems(provider: p, selected: model, onPick: onPick),
            ],
            child: Text(p.displayName),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined, size: 18),
          onPressed: () =>
              ref.read(navigationProvider.notifier).go(AppDestination.settings),
          child: Text(l.aiManageProviders),
        ),
      ],
      builder: (context, controller, _) => TextButton.icon(
        key: const ValueKey('ai-model-picker'),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.expand_more, size: 18),
        label: Text(
          model?.model ?? l.aiPickModel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ModelItems extends ConsumerWidget {
  const _ModelItems({
    required this.provider,
    required this.selected,
    required this.onPick,
  });

  final AiProvider provider;
  final AiModelRef? selected;
  final ValueChanged<AiModelRef> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final models = ref.watch(aiModelsProvider(provider.id));
    return models.when(
      loading: () => MenuItemButton(child: Text(l.aiLoadingModels)),
      error: (e, _) => MenuItemButton(
        leadingIcon: const Icon(Icons.refresh, size: 18),
        onPressed: () => ref.invalidate(aiModelsProvider(provider.id)),
        child: Text('${l.aiModelsFailed} · ${l.aiRetry}'),
      ),
      data: (list) => list.isEmpty
          ? MenuItemButton(child: Text(l.aiNoModels))
          : ConstrainedBox(
              // Long lists (OpenAI has dozens) scroll inside the menu.
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                // The menu has its own scroll view; don't share its
                // controller.
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in list)
                      MenuItemButton(
                        key: ValueKey('ai-model-$m'),
                        leadingIcon: Icon(
                          Icons.check,
                          size: 18,
                          color:
                              selected?.providerId == provider.id &&
                                  selected?.model == m
                              ? null
                              : Colors.transparent,
                        ),
                        onPressed: () =>
                            onPick((providerId: provider.id, model: m)),
                        child: Text(m),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.session,
    required this.showModel,
    required this.onApprove,
    required this.onDeny,
  });

  final AiMessage message;
  final TerminalSession session;
  final bool showModel;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onDeny;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    if (message.fromUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, left: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: SelectableText(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
            if (message.withTerminal)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal, size: 14, color: scheme.outline),
                    const SizedBox(width: 4),
                    Text(l.aiWithTerminal, style: small),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: showModel ? 14 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.model != null && showModel)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    Symbols.smart_toy,
                    size: 14,
                    fill: 1,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      message.model!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (message.reasoning.isNotEmpty)
            _Reasoning(text: message.reasoning, live: message.streaming),
          if (message.text.isNotEmpty)
            _RichReply(text: message.text, session: session),
          for (final t in message.tools)
            _ToolCard(
              key: ValueKey('ai-tool-${t.id}'),
              run: t,
              onApprove: () => onApprove(t.id),
              onDeny: () => onDeny(t.id),
            ),
          if (message.streaming &&
              message.text.isEmpty &&
              message.tools.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: ShapeMorphIndicator(size: 28),
              ),
            ),
          if (message.notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(switch (message.notice!) {
                AiNotice.refused => l.aiRefused,
                AiNotice.truncated => l.aiTruncated,
                AiNotice.stepLimit => l.aiStepLimit,
              }, style: small),
            ),
          if (message.error != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message.error == 'No API key' ? l.aiNoKey : message.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A command the assistant wants to run or ran: purpose, command, state,
/// and for commands waiting on the user, Allow / Decline.
class _ToolCard extends StatefulWidget {
  const _ToolCard({
    super.key,
    required this.run,
    required this.onApprove,
    required this.onDeny,
  });

  final AiToolRun run;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _showOutput = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final run = widget.run;
    final waiting = run.state == AiToolState.waiting;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final (Widget icon, String label, Color color) = switch (run.state) {
      AiToolState.waiting => (
        Icon(Icons.pan_tool_outlined, size: 14, color: scheme.tertiary),
        l.aiToolWaiting,
        scheme.tertiary,
      ),
      AiToolState.running => (
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
        l.aiToolRunning,
        scheme.primary,
      ),
      AiToolState.done => (
        Icon(
          (run.exitCode ?? 0) == 0 ? Icons.check_circle : Icons.cancel,
          size: 14,
          color: (run.exitCode ?? 0) == 0 ? scheme.primary : scheme.error,
        ),
        run.exitCode == null || run.tool != 'run_command'
            ? l.aiToolDone
            : (run.exitCode == 0 ? l.aiToolDone : l.aiToolExit(run.exitCode!)),
        (run.exitCode ?? 0) == 0 ? scheme.primary : scheme.error,
      ),
      AiToolState.denied => (
        Icon(Icons.block, size: 14, color: scheme.outline),
        l.aiToolDenied,
        scheme.outline,
      ),
      AiToolState.failed => (
        Icon(Icons.error_outline, size: 14, color: scheme.error),
        l.aiToolFailed,
        scheme.error,
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: waiting
            ? scheme.tertiaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: waiting ? scheme.tertiary : scheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                run.tool == 'read_terminal'
                    ? Icons.visibility_outlined
                    : Icons.terminal,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  run.tool == 'read_terminal'
                      ? l.aiToolReadTerminal
                      : l.aiToolRun,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              icon,
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
          if (run.host.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              l.aiToolOnHost(run.host),
              key: const ValueKey('ai-tool-host'),
              style: small,
            ),
          ],
          if (run.purpose.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(run.purpose, style: small),
          ],
          if (run.tool == 'run_command') ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: terminalThemeFor(scheme).background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: SelectableText(
                  // Hidden characters shown as <U+...>.
                  visibleCommand(run.command),
                  key: const ValueKey('ai-tool-command'),
                  style: TextStyle(
                    fontFamily: monoFontFamily,
                    fontFamilyFallback: monoFontFallback,
                    fontSize: 12.5,
                    color: terminalThemeFor(scheme).foreground,
                  ),
                ),
              ),
            ),
          ],
          if (hasHiddenCharacters(run.command)) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.visibility_off, size: 16, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.aiToolHiddenChars,
                    key: const ValueKey('ai-tool-hidden-chars'),
                    style: small?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
          ],
          if (waiting) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  run.readOnly ? Icons.info_outline : Icons.warning_amber,
                  size: 16,
                  color: run.readOnly
                      ? scheme.onSurfaceVariant
                      : scheme.tertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    run.readOnly ? l.aiToolAskAll : l.aiToolMayChange,
                    style: small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: ValueKey('ai-deny-${run.id}'),
                  onPressed: widget.onDeny,
                  child: Text(l.aiDeny),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: ValueKey('ai-approve-${run.id}'),
                  onPressed: widget.onApprove,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(l.aiAllow),
                ),
              ],
            ),
          ],
          if (run.state == AiToolState.done || run.state == AiToolState.failed)
            if (run.tool == 'run_command') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => setState(() => _showOutput = !_showOutput),
                  icon: Icon(
                    _showOutput ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  label: Text(_showOutput ? l.aiHideOutput : l.aiShowOutput),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topLeft,
                child: _showOutput
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                          primary: false,
                          child: SelectableText(
                            run.output.isEmpty ? l.aiNoOutput : run.output,
                            style: TextStyle(
                              fontFamily: monoFontFamily,
                              fontFamilyFallback: monoFontFallback,
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
        ],
      ),
    );
  }
}

class _Reasoning extends StatefulWidget {
  const _Reasoning({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.aiReasoning, style: style),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: style?.color,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 6),
                  child: SelectableText(widget.text, style: style),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A reply rendered as Markdown; code blocks get copy / paste into
/// terminal buttons. The whole reply can be selected.
class _RichReply extends StatelessWidget {
  const _RichReply({required this.text, required this.session});

  final String text;
  final TerminalSession session;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: MarkdownView(
      text: text,
      codeBlock: (language, code) =>
          _CodeBlock(language: language, code: code, session: session),
    ),
  );
}

/// Pastes [code] into [session]'s terminal without running it. Shells
/// without bracketed paste (bash 5.0 and older, ...) take each line break
/// as Enter, so a multi-line paste would run all but the last line: ask
/// first.
Future<void> pasteIntoTerminal(
  BuildContext context,
  TerminalSession session,
  String code,
) async {
  final lines = code.split('\n').length;
  if (lines > 1 && !session.terminal.bracketedPasteMode) {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text(l.aiPasteRunsTitle),
        content: Text(l.aiPasteRunsBody(lines - 1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('paste-anyway'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.aiPasteAnyway),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  session.terminal.paste(code);
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.session,
  });

  final String language;
  final String code;
  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final terminalTheme = terminalThemeFor(scheme);
    final connected = session.status == SessionStatus.connected;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: terminalTheme.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      language.isEmpty ? 'code' : language,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.copy,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(l.aiCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    key: const ValueKey('ai-paste-to-terminal'),
                    tooltip: l.aiPasteToTerminal,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.input),
                    // Pasted without Enter: the user reviews and runs it.
                    onPressed: connected
                        ? () => pasteIntoTerminal(context, session, code)
                        : null,
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                code,
                style: TextStyle(
                  fontFamily: monoFontFamily,
                  fontFamilyFallback: monoFontFallback,
                  fontSize: 12.5,
                  height: 1.4,
                  color: terminalTheme.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
