import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/toasts.dart';
import '../terminal/sessions_providers.dart';
import '../terminal/terminal_session.dart';
import 'snippet.dart';
import 'snippet_editor_sheet.dart';
import 'snippet_runner.dart';
import 'snippets_providers.dart';

/// Search bar and "new snippet" button share the workbench header height.
const _actionHeight = 44.0;

class SnippetsPage extends ConsumerStatefulWidget {
  const SnippetsPage({super.key});

  @override
  ConsumerState<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends ConsumerState<SnippetsPage> {
  String _query = '';
  SnippetLanguage? _languageFilter;
  String? _groupFilter;

  List<Snippet> _filtered(List<Snippet> all) {
    return [
      for (final s in all)
        if (_matches(s)) s,
    ];
  }

  bool _matches(Snippet s) {
    if (_languageFilter != null && s.language != _languageFilter) return false;
    if (_groupFilter != null && s.group != _groupFilter) return false;
    if (_query.isEmpty) return true;
    final q = _query;
    return s.name.toLowerCase().contains(q) ||
        s.content.toLowerCase().contains(q) ||
        (s.description?.toLowerCase().contains(q) ?? false) ||
        (s.group?.toLowerCase().contains(q) ?? false);
  }

  Future<void> _sendToActiveTerminal(Snippet snippet) async {
    final l = context.l10n;
    final sessions = ref.read(sessionsProvider);
    final active = sessions.active;
    final target = active != null && active.status == SessionStatus.connected
        ? active
        : sessions.sessions
              .where((s) => s.status == SessionStatus.connected)
              .firstOrNull;
    if (target == null) {
      showToast(l.snippetNoActiveTerminal, kind: ToastKind.error);
      return;
    }
    final sent = await runOrInsertSnippet(
      context,
      snippet: snippet,
      session: target,
      execute: true,
    );
    if (!sent || !mounted) return;
    ref.read(sessionsProvider.notifier).activate(target.id);
    showToast(l.snippetSent(target.host.displayName), kind: ToastKind.success);
  }

  Future<void> _copySnippet(Snippet snippet) async {
    final copiedText = context.l10n.snippetCopied;
    await Clipboard.setData(ClipboardData(text: snippet.content));
    showToast(copiedText, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final snippetsAsync = ref.watch(snippetsProvider);
    final hasConnectedSession = ref.watch(
      sessionsProvider.select(
        (s) => s.sessions.any((t) => t.status == SessionStatus.connected),
      ),
    );

    return PageScaffold(
      title: l.snippetsTitle,
      actions: [
        SizedBox(
          width: 260,
          height: _actionHeight,
          child: SearchBar(
            key: const ValueKey('snippets-search'),
            hintText: l.searchSnippets,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints.tightFor(height: _actionHeight),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: _actionHeight,
          child: FilledButton.icon(
            key: const ValueKey('new-snippet-button'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            onPressed: () => openSnippetEditor(ref),
            icon: const Icon(Icons.add),
            label: Text(l.newSnippet),
          ),
        ),
      ],
      child: snippetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: l.loadSnippetsFailed,
          message: '$e',
        ),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.code_outlined,
              title: l.noSnippetsTitle,
              message: l.noSnippetsMessage,
            );
          }
          final usedLanguages = {for (final s in all) s.language};
          final groups = {
            for (final s in all)
              if (s.group != null && s.group!.isNotEmpty) s.group!,
          }.toList()..sort();
          final items = _filtered(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (usedLanguages.length > 1 || groups.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(l.snippetLangAll),
                      selected: _languageFilter == null && _groupFilter == null,
                      onSelected: (_) => setState(() {
                        _languageFilter = null;
                        _groupFilter = null;
                      }),
                    ),
                    for (final lang in SnippetLanguage.values)
                      if (usedLanguages.contains(lang))
                        FilterChip(
                          label: Text(snippetLanguageLabel(l, lang)),
                          selected: _languageFilter == lang,
                          onSelected: (selected) => setState(
                            () => _languageFilter = selected ? lang : null,
                          ),
                        ),
                    for (final g in groups)
                      FilterChip(
                        avatar: const Icon(Icons.label_outline, size: 16),
                        label: Text(g),
                        selected: _groupFilter == g,
                        onSelected: (selected) =>
                            setState(() => _groupFilter = selected ? g : null),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off,
                        title: l.noMatchesTitle,
                        message: l.noMatchesMessage,
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              mainAxisExtent: 152,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final snippet = items[i];
                          return _SnippetCard(
                            snippet: snippet,
                            canRun: hasConnectedSession,
                            onEdit: () =>
                                openSnippetEditor(ref, snippet: snippet),
                            onCopy: () => _copySnippet(snippet),
                            onRun: () => _sendToActiveTerminal(snippet),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SnippetCard extends StatelessWidget {
  const _SnippetCard({
    required this.snippet,
    required this.canRun,
    required this.onEdit,
    required this.onCopy,
    required this.onRun,
  });

  final Snippet snippet;
  final bool canRun;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = snippetLanguageVisual(scheme, snippet.language);

    return Card(
      key: ValueKey('snippet-card-${snippet.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: visual.bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      snippetLanguageTag(snippet.language),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: visual.fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      snippet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (snippet.group != null && snippet.group!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        snippet.group!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: canRun
                        ? l.snippetSendToTerminal
                        : l.snippetNoActiveTerminal,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: canRun ? onRun : null,
                  ),
                  IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.content_copy_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onCopy,
                  ),
                  IconButton(
                    tooltip: l.edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                  ),
                ],
              ),
              if (snippet.description != null &&
                  snippet.description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    snippet.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    snippet.content.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: monoFontFamily,
                      fontFamilyFallback: monoFontFallback,
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
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
