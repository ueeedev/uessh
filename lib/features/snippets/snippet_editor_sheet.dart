import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/app_dropdown.dart';
import 'code_editor.dart';
import 'snippet.dart';
import 'snippet_editor_tabs.dart';
import 'snippets_providers.dart';

/// Full localized label for [language].
String snippetLanguageLabel(AppLocalizations l, SnippetLanguage language) =>
    switch (language) {
      SnippetLanguage.shell => l.snippetLangShell,
      SnippetLanguage.bash => l.snippetLangBash,
      SnippetLanguage.python => l.snippetLangPython,
      SnippetLanguage.powershell => l.snippetLangPowerShell,
      SnippetLanguage.node => l.snippetLangNode,
      SnippetLanguage.other => l.snippetLangOther,
    };

/// Short badge text for cards, compact lists, and editor tabs.
String snippetLanguageTag(SnippetLanguage language) => switch (language) {
  SnippetLanguage.shell => 'SH',
  SnippetLanguage.bash => 'BASH',
  SnippetLanguage.python => 'PY',
  SnippetLanguage.powershell => 'PS1',
  SnippetLanguage.node => 'JS',
  SnippetLanguage.other => 'TXT',
};

/// Accent colors for a language badge that fit both light and dark M3 schemes.
({Color bg, Color fg, IconData icon}) snippetLanguageVisual(
  ColorScheme scheme,
  SnippetLanguage language,
) => switch (language) {
  SnippetLanguage.shell => (
    bg: scheme.primaryContainer,
    fg: scheme.onPrimaryContainer,
    icon: Icons.terminal,
  ),
  SnippetLanguage.bash => (
    bg: scheme.secondaryContainer,
    fg: scheme.onSecondaryContainer,
    icon: Icons.terminal,
  ),
  SnippetLanguage.python => (
    bg: scheme.tertiaryContainer,
    fg: scheme.onTertiaryContainer,
    icon: Icons.code,
  ),
  SnippetLanguage.powershell => (
    bg: scheme.primaryContainer,
    fg: scheme.onPrimaryContainer,
    icon: Icons.data_object,
  ),
  SnippetLanguage.node => (
    bg: scheme.secondaryContainer,
    fg: scheme.onSecondaryContainer,
    icon: Icons.javascript,
  ),
  SnippetLanguage.other => (
    bg: scheme.surfaceContainerHighest,
    fg: scheme.onSurfaceVariant,
    icon: Icons.notes,
  ),
};

String _executionHint(AppLocalizations l, SnippetLanguage language) =>
    switch (language) {
      SnippetLanguage.shell => l.snippetExecShellHint,
      SnippetLanguage.bash => l.snippetExecBashHint,
      SnippetLanguage.python => l.snippetExecPythonHint,
      SnippetLanguage.powershell => l.snippetExecPowerShellHint,
      SnippetLanguage.node => l.snippetExecNodeHint,
      SnippetLanguage.other => l.snippetExecOtherHint,
    };

/// Opens a snippet editor tab in the main window's top tab strip.
void openSnippetEditor(WidgetRef ref, {Snippet? snippet}) {
  ref.read(snippetEditorsProvider.notifier).open(snippet: snippet);
}

/// Two-pane snippet IDE workspace embedded directly inside a browser-style
/// window tab: VS Code-style code editor on the left, metadata inspector and
/// action footer on the right.
class SnippetEditorView extends ConsumerStatefulWidget {
  const SnippetEditorView({super.key, required this.tab});

  final SnippetEditorTab tab;

  @override
  ConsumerState<SnippetEditorView> createState() => _SnippetEditorViewState();
}

class _SnippetEditorViewState extends ConsumerState<SnippetEditorView> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.tab.initialSnippet?.name ?? '',
  );
  late final _group = TextEditingController(
    text: widget.tab.initialSnippet?.group ?? '',
  );
  late final _description = TextEditingController(
    text: widget.tab.initialSnippet?.description ?? '',
  );
  late final _content = SyntaxHighlightingController(
    text: widget.tab.initialSnippet?.content ?? '',
    language: widget.tab.initialSnippet?.language ?? SnippetLanguage.shell,
  );
  late SnippetLanguage _language =
      widget.tab.initialSnippet?.language ?? SnippetLanguage.shell;

  bool _saving = false;
  bool _dirty = false;
  String? _contentError;
  late String _lastContentText = _content.text;
  late final List<Object> _initial;

  Snippet? get _snippet => widget.tab.initialSnippet;
  bool get _isEdit => _snippet != null;

  List<Object> _snapshot() => [
    _name.text,
    _group.text,
    _description.text,
    _content.text,
    _language,
  ];

  void _syncTabMeta() {
    ref
        .read(snippetEditorsProvider.notifier)
        .updateMeta(
          widget.tab.id,
          name: _name.text,
          language: _language,
          dirty: _dirty,
        );
  }

  void _updateDirty() {
    final snap = _snapshot();
    final dirty = Iterable<int>.generate(snap.length)
        .any((i) => snap[i] != _initial[i]);
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    }
    _syncTabMeta();
  }

  void _onContentChanged() {
    if (!mounted) return;
    if (_content.text == _lastContentText) return;
    _lastContentText = _content.text;
    if (_contentError != null && _content.text.trim().isNotEmpty) {
      _contentError = null;
    }
    _updateDirty();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _initial = _snapshot();
    _name.addListener(_updateDirty);
    _group.addListener(_updateDirty);
    _description.addListener(_updateDirty);
    _content.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_updateDirty);
    _group.removeListener(_updateDirty);
    _description.removeListener(_updateDirty);
    _content.removeListener(_onContentChanged);
    for (final c in [_name, _group, _description, _content]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setLanguage(SnippetLanguage lang) {
    setState(() {
      _language = lang;
      _content.language = lang;
    });
    _updateDirty();
  }

  Future<void> _importFile() async {
    final file = await openFile(
      confirmButtonText: context.l10n.importAction,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Scripts',
          extensions: ['sh', 'bash', 'zsh', 'py', 'ps1', 'js', 'mjs', 'txt'],
        ),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    if (!mounted) return;
    setState(() {
      _content.text = text;
      _lastContentText = text;
      _contentError = null;
      final guessed = SnippetLanguage.fromFileName(file.name);
      if (guessed != SnippetLanguage.other) {
        _language = guessed;
        _content.language = guessed;
      }
      if (_name.text.trim().isEmpty) {
        final dot = file.name.lastIndexOf('.');
        _name.text = dot > 0 ? file.name.substring(0, dot) : file.name;
      }
    });
    _updateDirty();
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final contentEmpty = _content.text.trim().isEmpty;
    if (contentEmpty) {
      setState(() => _contentError = context.l10n.snippetContentRequired);
    }
    if (!formOk || contentEmpty) return;

    setState(() => _saving = true);
    final group = _group.text.trim();
    final desc = _description.text.trim();
    final snippet = Snippet(
      id: _snippet?.id ?? Snippet.newId(),
      name: _name.text.trim(),
      language: _language,
      content: _content.text,
      group: group.isEmpty ? null : group,
      description: desc.isEmpty ? null : desc,
    );
    await ref.read(snippetsProvider.notifier).save(snippet);
    if (mounted) {
      ref.read(snippetEditorsProvider.notifier).close(widget.tab.id);
    }
  }

  Future<void> _delete() async {
    final snippet = _snippet!;
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(l.deleteSnippetTitle(snippet.name)),
        content: Text(l.deleteSnippetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await ref.read(snippetsProvider.notifier).remove(snippet.id);
    if (mounted) {
      ref.read(snippetEditorsProvider.notifier).close(widget.tab.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = snippetLanguageVisual(scheme, _language);
    final placeholders = extractPlaceholders(_content.text);
    final existingGroups = {
      for (final s in ref.watch(snippetsProvider).value ?? const <Snippet>[])
        if (s.group != null && s.group!.isNotEmpty) s.group!,
    }.toList()..sort();
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyS,
          meta: isMac,
          control: !isMac,
        ): () {
          if (!_saving) _save();
        },
      },
      child: Material(
        key: const ValueKey('snippet-editor-window'),
        color: terminalThemeFor(scheme).background,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left pane: VS Code-style code editor.
            Expanded(
              child: SnippetCodeEditor(
                controller: _content,
                fieldKey: const ValueKey('snippet-content-field'),
                languageLabel: snippetLanguageLabel(l, _language),
                hintText: l.snippetContentHint('{{name}}'),
                errorText: _contentError,
                autofocus: _isEdit,
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
            // Right pane: snippet info form + bottom action buttons.
            SizedBox(
              key: const ValueKey('snippet-info-pane'),
              width: 320,
              child: ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            Text(
                              l.snippetInfoTitle,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('snippet-name-field'),
                              controller: _name,
                              autofocus: !_isEdit,
                              decoration: InputDecoration(
                                labelText: l.snippetName,
                                hintText: l.snippetNameHint,
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? l.snippetNameRequired
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l.snippetLanguage,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AppDropdown<SnippetLanguage>(
                              key: const ValueKey('snippet-language-dropdown'),
                              value: _language,
                              onChanged: _setLanguage,
                              entries: [
                                for (final lang in SnippetLanguage.values)
                                  AppDropdownEntry(
                                    value: lang,
                                    label: snippetLanguageLabel(l, lang),
                                    icon: snippetLanguageVisual(
                                      scheme,
                                      lang,
                                    ).icon,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('snippet-group-field'),
                              controller: _group,
                              decoration: InputDecoration(
                                labelText: l.snippetGroup,
                                hintText: l.snippetGroupHint,
                              ),
                            ),
                            if (existingGroups.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final g in existingGroups)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(g),
                                      onPressed: () {
                                        _group.text = g;
                                        _updateDirty();
                                      },
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              key: const ValueKey('snippet-desc-field'),
                              controller: _description,
                              minLines: 2,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: l.snippetDescription,
                                hintText: l.snippetDescriptionHint,
                                alignLabelWithHint: true,
                              ),
                            ),
                            if (placeholders.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Text(
                                l.snippetPlaceholdersHint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final name in placeholders)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        '{{$name}}',
                                        style: TextStyle(
                                          fontFamily: monoFontFamily,
                                          fontFamilyFallback: monoFontFallback,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        visual.icon,
                                        size: 16,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        l.snippetExecutionTitle,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(color: scheme.onSurface),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _executionHint(l, _language),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Bottom footer of the right info pane: Import from file,
                    // Delete (when editing), Cancel, Save.
                    Container(
                      key: const ValueKey('snippet-info-footer'),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey('snippet-import-file'),
                                  onPressed: _saving ? null : _importFile,
                                  icon: const Icon(
                                    Icons.file_open_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    l.snippetImportFile,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (_isEdit) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  key: const ValueKey('delete-snippet'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: scheme.error,
                                    side: BorderSide(
                                      color: scheme.error.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  onPressed: _saving ? null : _delete,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: Text(l.delete),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  key: const ValueKey('cancel-snippet'),
                                  onPressed: _saving
                                      ? null
                                      : () => requestCloseSnippetEditor(
                                          context,
                                          ref,
                                          widget.tab,
                                        ),
                                  child: Text(l.cancel),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  key: const ValueKey('save-snippet'),
                                  onPressed: _saving ? null : _save,
                                  child: Text(l.save),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
