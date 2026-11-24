import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../terminal/terminal_session.dart';
import 'snippet.dart';
import 'snippet_editor_sheet.dart';
import 'snippet_runner.dart';
import 'snippets_providers.dart';

/// Side panel beside the terminal for quickly searching, running, or inserting
/// saved commands and scripts into [session].
class SnippetsPanel extends ConsumerStatefulWidget {
  const SnippetsPanel({
    super.key,
    required this.session,
    required this.onClose,
  });

  final TerminalSession session;
  final VoidCallback onClose;

  @override
  ConsumerState<SnippetsPanel> createState() => _SnippetsPanelState();
}

class _SnippetsPanelState extends ConsumerState<SnippetsPanel> {
  String _query = '';
  SnippetLanguage? _language;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(SnippetsPanel old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  bool _matches(Snippet s) {
    if (_language != null && s.language != _language) return false;
    if (_query.isEmpty) return true;
    return s.name.toLowerCase().contains(_query) ||
        s.content.toLowerCase().contains(_query) ||
        (s.group?.toLowerCase().contains(_query) ?? false) ||
        (s.description?.toLowerCase().contains(_query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snippetsAsync = ref.watch(snippetsProvider);
    final connected = widget.session.status == SessionStatus.connected;

    return Material(
      key: const ValueKey('snippets-panel'),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.snippetsTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('snippets-panel-add'),
                  tooltip: l.newSnippet,
                  icon: const Icon(Icons.add),
                  onPressed: () => openSnippetEditor(ref),
                ),
                IconButton(
                  tooltip: l.closeSnippetsPanel,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              key: const ValueKey('snippets-panel-search'),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l.searchSnippets,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
          if (!connected)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l.snippetConnectFirst,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(
            child: snippetsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$e', style: theme.textTheme.bodySmall),
                ),
              ),
              data: (all) {
                if (all.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.code_outlined,
                            size: 32,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.noSnippetsTitle,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.noSnippetsMessage,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final usedLanguages = {for (final s in all) s.language};
                final filtered = [
                  for (final s in all)
                    if (_matches(s)) s,
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (usedLanguages.length > 1)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(l.snippetLangAll),
                                selected: _language == null,
                                onSelected: (_) =>
                                    setState(() => _language = null),
                              ),
                            ),
                            for (final lang in SnippetLanguage.values)
                              if (usedLanguages.contains(lang))
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(snippetLanguageTag(lang)),
                                    selected: _language == lang,
                                    onSelected: (selected) => setState(
                                      () => _language = selected ? lang : null,
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                l.noMatchesTitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final s = filtered[i];
                                final visual = snippetLanguageVisual(
                                  scheme,
                                  s.language,
                                );
                                return Card.filled(
                                  key: ValueKey('panel-snippet-${s.id}'),
                                  margin: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      4,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: visual.bg,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                snippetLanguageTag(s.language),
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: visual.fg,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                s.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.labelLarge,
                                              ),
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'panel-snippet-run-${s.id}',
                                              ),
                                              tooltip: l.snippetRun,
                                              icon: const Icon(
                                                Icons.play_arrow_rounded,
                                                size: 18,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: connected
                                                  ? () => runOrInsertSnippet(
                                                      context,
                                                      snippet: s,
                                                      session: widget.session,
                                                      execute: true,
                                                    )
                                                  : null,
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'panel-snippet-insert-${s.id}',
                                              ),
                                              tooltip: l.snippetInsert,
                                              icon: const Icon(
                                                Icons.input_rounded,
                                                size: 16,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: connected
                                                  ? () => runOrInsertSnippet(
                                                      context,
                                                      snippet: s,
                                                      session: widget.session,
                                                      execute: false,
                                                    )
                                                  : null,
                                            ),
                                            IconButton(
                                              tooltip: l.edit,
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 16,
                                              ),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () =>
                                                  openSnippetEditor(
                                                    ref,
                                                    snippet: s,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Text(
                                            s.content.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: monoFontFamily,
                                              fontFamilyFallback:
                                                  monoFontFallback,
                                              fontSize: 11.5,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
