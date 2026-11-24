import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../terminal/sessions_providers.dart';
import 'snippet.dart';

/// One open snippet editor tab in the main window's top tab strip.
class SnippetEditorTab {
  const SnippetEditorTab({
    required this.id,
    this.initialSnippet,
    required this.name,
    required this.language,
    this.dirty = false,
  });

  /// Unique tab id (distinct from [Snippet.id] so multiple new-snippet tabs
  /// can be open at the same time).
  final String id;

  /// Existing snippet being edited, or null for a brand-new snippet.
  final Snippet? initialSnippet;

  /// Live draft name shown on the tab strip.
  final String name;

  /// Live draft language shown on the tab strip.
  final SnippetLanguage language;

  /// Whether the draft currently differs from its initial state.
  final bool dirty;

  String? get snippetId => initialSnippet?.id;
  bool get isEdit => initialSnippet != null;

  /// Tab title formatted like a script filename, e.g. `deploy.sh` or
  /// `untitled.py`.
  String displayFileName(String untitledFallback) {
    final trimmed = name.trim();
    final base = trimmed.isEmpty ? untitledFallback : trimmed;
    return base.contains('.') ? base : '$base.${language.extension}';
  }

  SnippetEditorTab copyWith({
    String? name,
    SnippetLanguage? language,
    bool? dirty,
  }) => SnippetEditorTab(
    id: id,
    initialSnippet: initialSnippet,
    name: name ?? this.name,
    language: language ?? this.language,
    dirty: dirty ?? this.dirty,
  );
}

class SnippetEditorsState {
  const SnippetEditorsState({this.tabs = const [], this.activeTabId});

  final List<SnippetEditorTab> tabs;

  /// Active editor tab id, or null when the user is viewing the workbench or
  /// an SSH tab.
  final String? activeTabId;

  bool get hasActive => activeTab != null;

  SnippetEditorTab? get activeTab => tabById(activeTabId);

  SnippetEditorTab? tabById(String? id) {
    if (id == null) return null;
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }
}

class SnippetEditorsNotifier extends Notifier<SnippetEditorsState> {
  @override
  SnippetEditorsState build() {
    // Switching to an SSH tab, opening a new session, or explicitly returning
    // to the workbench brings that view to the front while keeping open editor
    // tabs alive in the strip.
    ref.listen<SessionsState>(sessionsProvider, (prev, next) {
      if (!state.hasActive) return;
      final openedNewSession =
          prev != null && next.sessions.length > prev.sessions.length;
      final activatedSsh =
          !next.homeActive &&
          (prev == null ||
              prev.homeActive ||
              prev.activeTabId != next.activeTabId);
      final wentHome = next.homeActive && prev != null && !prev.homeActive;
      if (openedNewSession || activatedSsh || wentHome) {
        deactivate();
      }
    });
    return const SnippetEditorsState();
  }

  /// Opens an editor tab for [snippet], or a fresh untitled snippet tab when
  /// [snippet] is null. Reuses an already-open tab for the same [snippet.id].
  SnippetEditorTab open({Snippet? snippet}) {
    if (snippet != null) {
      for (final existing in state.tabs) {
        if (existing.snippetId == snippet.id) {
          state = SnippetEditorsState(
            tabs: state.tabs,
            activeTabId: existing.id,
          );
          return existing;
        }
      }
    }
    final tab = SnippetEditorTab(
      id: Snippet.newId(),
      initialSnippet: snippet,
      name: snippet?.name ?? '',
      language: snippet?.language ?? SnippetLanguage.shell,
    );
    state = SnippetEditorsState(
      tabs: [...state.tabs, tab],
      activeTabId: tab.id,
    );
    return tab;
  }

  void activate(String tabId) {
    if (state.tabById(tabId) == null) return;
    if (state.activeTabId == tabId) return;
    state = SnippetEditorsState(tabs: state.tabs, activeTabId: tabId);
  }

  /// Hides the active editor view (returning to the workbench or SSH tab)
  /// without closing any editor tabs.
  void deactivate() {
    if (state.activeTabId == null) return;
    state = SnippetEditorsState(tabs: state.tabs, activeTabId: null);
  }

  /// Updates the live tab strip metadata for [tabId] without touching state
  /// when nothing changed.
  void updateMeta(
    String tabId, {
    String? name,
    SnippetLanguage? language,
    bool? dirty,
  }) {
    final i = state.tabs.indexWhere((t) => t.id == tabId);
    if (i < 0) return;
    final current = state.tabs[i];
    final nextName = name ?? current.name;
    final nextLang = language ?? current.language;
    final nextDirty = dirty ?? current.dirty;
    if (nextName == current.name &&
        nextLang == current.language &&
        nextDirty == current.dirty) {
      return;
    }
    final nextTabs = [...state.tabs];
    nextTabs[i] = current.copyWith(
      name: nextName,
      language: nextLang,
      dirty: nextDirty,
    );
    state = SnippetEditorsState(tabs: nextTabs, activeTabId: state.activeTabId);
  }

  /// Closes [tabId], activating an adjacent editor tab if [tabId] was active
  /// and other editor tabs remain, or falling back to the workbench / SSH view.
  void close(String tabId) {
    final i = state.tabs.indexWhere((t) => t.id == tabId);
    if (i < 0) return;
    final nextTabs = [...state.tabs]..removeAt(i);
    String? nextActive = state.activeTabId;
    if (state.activeTabId == tabId) {
      if (nextTabs.isEmpty) {
        nextActive = null;
      } else {
        nextActive = nextTabs[i < nextTabs.length ? i : nextTabs.length - 1].id;
      }
    }
    state = SnippetEditorsState(tabs: nextTabs, activeTabId: nextActive);
  }
}

final snippetEditorsProvider =
    NotifierProvider<SnippetEditorsNotifier, SnippetEditorsState>(
      SnippetEditorsNotifier.new,
    );

bool _askingCloseEditor = false;

/// Closes [tab], prompting for confirmation first when it has unsaved edits.
Future<void> requestCloseSnippetEditor(
  BuildContext context,
  WidgetRef ref,
  SnippetEditorTab tab,
) async {
  if (!tab.dirty) {
    ref.read(snippetEditorsProvider.notifier).close(tab.id);
    return;
  }
  if (_askingCloseEditor) return;
  _askingCloseEditor = true;
  try {
    final l = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.edit_off_outlined),
        title: Text(l.discardChangesTitle),
        content: Text(l.discardChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.discardChanges),
          ),
        ],
      ),
    );
    if (discard == true) {
      ref.read(snippetEditorsProvider.notifier).close(tab.id);
    }
  } finally {
    _askingCloseEditor = false;
  }
}
