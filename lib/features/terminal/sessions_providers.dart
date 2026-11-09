import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import '../keys/keys_providers.dart';
import '../settings/settings_providers.dart';
import 'known_hosts.dart';
import 'session_prompts.dart';
import 'command_highlight.dart';
import 'terminal_session.dart';
import 'workspace_layout.dart';

final knownHostsProvider = Provider<KnownHostsStore>(
  (ref) => KnownHostsStore(dataDir: ref.watch(dataDirProvider)),
);

final sessionPromptsProvider = Provider<SessionPrompts>(
  (ref) => DialogSessionPrompts(rootNavigatorKey),
);

/// Makes the session for a host being opened (replaceable in tests).
final sessionFactoryProvider = Provider<TerminalSession Function(Host)>(
  (ref) =>
      (host) => host.id == localHostId
      ? LocalTerminalSession(
          host: host,
          repository: ref.read(hostRepositoryProvider),
          knownHosts: ref.read(knownHostsProvider),
          prompts: ref.read(sessionPromptsProvider),
        )
      : TerminalSession(
          host: host,
          repository: ref.read(hostRepositoryProvider),
          knownHosts: ref.read(knownHostsProvider),
          prompts: ref.read(sessionPromptsProvider),
          keys: ref.read(keyRepositoryProvider),
        ),
);

/// One terminal tab: a workspace of one or more panes laid out in a
/// split tree.
class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.layout,
    required this.focusedId,
    this.zoomedId,
    this.broadcast = false,
    this.name,
    this.number,
  });

  final String id;

  /// Name the user gave the workspace (null: "Workspace [number]").
  final String? name;

  /// Number for the default name, given when the tab first gets a second
  /// pane; the smallest one no other workspace uses.
  final int? number;
  final LayoutNode layout;

  /// The pane that gets keyboard input (and the side panels).
  final String focusedId;

  /// A pane shown alone, filling the workspace (null: all panes shown).
  final String? zoomedId;

  /// Typing in one pane goes to every pane of the tab.
  final bool broadcast;

  List<String> get paneIds => layout.panes;
  bool get isSplit => layout is SplitNode;

  WorkspaceTab copyWith({
    LayoutNode? layout,
    String? focusedId,
    Object? zoomedId = _keep,
    bool? broadcast,
    Object? name = _keep,
    Object? number = _keep,
  }) => WorkspaceTab(
    id: id,
    layout: layout ?? this.layout,
    focusedId: focusedId ?? this.focusedId,
    zoomedId: identical(zoomedId, _keep) ? this.zoomedId : zoomedId as String?,
    broadcast: broadcast ?? this.broadcast,
    name: identical(name, _keep) ? this.name : name as String?,
    number: identical(number, _keep) ? this.number : number as int?,
  );

  static const _keep = Object();
}

class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.tabs = const [],
    this.activeTabId,
    this.home = true,
  });

  /// Every open session, in the order opened.
  final List<TerminalSession> sessions;
  final List<WorkspaceTab> tabs;
  final String? activeTabId;

  /// The workbench (first, pinned tab) is shown. [activeTabId] still
  /// names the SSH tab to come back to.
  final bool home;

  /// Showing the workbench (also when there are no SSH tabs).
  bool get homeActive => home || activeTab == null;

  WorkspaceTab? get activeTab => tabById(activeTabId);

  /// The focused pane of the current tab.
  TerminalSession? get active => session(activeTab?.focusedId);
  String? get activeId => active?.id;

  TerminalSession? session(String? id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  WorkspaceTab? tabById(String? id) {
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The tab holding session [sessionId].
  WorkspaceTab? tabOf(String sessionId) {
    for (final t in tabs) {
      if (t.layout.contains(sessionId)) return t;
    }
    return null;
  }

  SessionsState copyWith({
    List<TerminalSession>? sessions,
    List<WorkspaceTab>? tabs,
    String? activeTabId,
    bool? home,
  }) => SessionsState(
    sessions: sessions ?? this.sessions,
    tabs: tabs ?? this.tabs,
    activeTabId: activeTabId ?? this.activeTabId,
    // Activating an SSH tab leaves the workbench.
    home: home ?? (activeTabId != null ? false : this.home),
  );
}

class SessionsNotifier extends Notifier<SessionsState> {
  // Kept outside `state` because onDispose may not read state.
  final _open = <TerminalSession>{};

  @override
  SessionsState build() {
    ref.onDispose(() {
      for (final s in _open) {
        s.dispose();
      }
      _open.clear();
    });
    return const SessionsState();
  }

  /// Opens a shell on this computer in a new tab.
  TerminalSession openLocal() => open(localHost());

  /// Opens [host] in a new tab, or - with [splitFrom] - as a new pane
  /// beside that pane on [side]. Falls back to a new tab when the
  /// workspace is full.
  TerminalSession open(
    Host host, {
    String? splitFrom,
    DropSide side = DropSide.right,
  }) {
    final session = ref.read(sessionFactoryProvider)(host);
    _open.add(session);
    if (!session.isLocal) _recordLastConnected(session);
    // Read the settings at each drop, so changes apply to open tabs too.
    session.reconnectPolicy ??= () => ref.mounted
        ? ref.read(settingsProvider).reconnect
        : (enabled: false, attempts: 0, delay: Duration.zero);
    session.highlightSettings ??= () => ref.mounted
        ? ref.read(settingsProvider).highlight
        : (enabled: false, colors: const <HighlightToken, int>{});

    final target = splitFrom == null ? null : state.tabOf(splitFrom);
    if (target != null &&
        target.paneIds.length < maxPanes &&
        side != DropSide.center) {
      _set(
        state.copyWith(
          sessions: [...state.sessions, session],
          tabs: _replaceTab(
            target.copyWith(
              layout: insertPane(target.layout, splitFrom!, session.id, side),
              focusedId: session.id,
              zoomedId: null,
            ),
          ),
          activeTabId: target.id,
        ),
      );
    } else {
      final tab = WorkspaceTab(
        id: Host.newId(),
        layout: PaneNode(session.id),
        focusedId: session.id,
      );
      _set(
        state.copyWith(
          sessions: [...state.sessions, session],
          tabs: [...state.tabs, tab],
          activeTabId: tab.id,
        ),
      );
    }
    session.connect();
    return session;
  }

  /// Remembers the host each time this session's connection comes up
  /// (for "last connected" on the hosts page).
  void _recordLastConnected(TerminalSession session) {
    var wasConnected = false;
    session.addListener(() {
      final connected = session.status == SessionStatus.connected;
      if (connected && !wasConnected && ref.mounted) {
        ref
            .read(settingsProvider.notifier)
            .update(
              (s) => s.withLastConnected(session.host.id, DateTime.now()),
            );
      }
      wasConnected = connected;
    });
  }

  /// Shows session [id]: its tab becomes current and the pane focused.
  void activate(String id) {
    final tab = state.tabOf(id);
    if (tab == null) return;
    _set(
      state.copyWith(
        tabs: _replaceTab(
          tab.copyWith(
            focusedId: id,
            // Focusing a hidden pane brings the others back.
            zoomedId: tab.zoomedId == null || tab.zoomedId == id
                ? tab.zoomedId
                : null,
          ),
        ),
        activeTabId: tab.id,
      ),
    );
  }

  /// Shows the workbench tab.
  void showHome() {
    if (!state.home) _set(state.copyWith(home: true));
  }

  void activateTab(String tabId) {
    if (state.tabById(tabId) == null) return;
    _set(state.copyWith(activeTabId: tabId));
  }

  /// Moves focus to the neighbouring pane in [direction].
  void focusNeighbour(PaneDirection direction) {
    final tab = state.activeTab;
    if (tab == null || tab.zoomedId != null) return;
    final next = neighbourPane(tab.layout, tab.focusedId, direction);
    if (next != null) activate(next);
  }

  /// Closes session [id] (its pane; the tab too when it was the last).
  void close(String id) {
    final removed = state.session(id);
    final tab = state.tabOf(id);
    if (removed == null) return;
    final sessions = [...state.sessions]..remove(removed);
    var tabs = [...state.tabs];
    var activeTabId = state.activeTabId;
    if (tab != null) {
      final layout = removePane(tab.layout, id);
      final index = tabs.indexWhere((t) => t.id == tab.id);
      if (layout == null) {
        tabs.removeAt(index);
        if (activeTabId == tab.id) {
          activeTabId = tabs.isEmpty
              ? null
              : tabs[index.clamp(0, tabs.length - 1)].id;
        }
      } else {
        // Focus moves to the pane that took the space.
        final order = tab.paneIds;
        final at = order.indexOf(id);
        final remaining = layout.panes;
        final focus = tab.focusedId == id
            ? remaining[(at - 1).clamp(0, remaining.length - 1)]
            : tab.focusedId;
        tabs[index] = tab.copyWith(
          layout: layout,
          focusedId: focus,
          zoomedId: tab.zoomedId == id ? null : tab.zoomedId,
        );
      }
    }
    _set(
      SessionsState(
        sessions: sessions,
        tabs: tabs,
        activeTabId: activeTabId,
        home: tabs.isEmpty || state.home,
      ),
    );
    _open.remove(removed);
    removed.dispose();
  }

  /// Closes every pane of tab [tabId].
  void closeTab(String tabId) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    for (final id in tab.paneIds) {
      close(id);
    }
  }

  /// Sets the sizes of a split in tab [tabId] (see [setWeights]).
  void resize(String tabId, List<int> path, List<double> weights) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    _set(
      state.copyWith(
        tabs: _replaceTab(
          tab.copyWith(layout: setWeights(tab.layout, path, weights)),
        ),
      ),
    );
  }

  void equalizeTab(String tabId) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    _set(
      state.copyWith(
        tabs: _replaceTab(tab.copyWith(layout: equalize(tab.layout))),
      ),
    );
  }

  /// Shows only pane [id] in its tab, or all panes again.
  void toggleZoom(String id) {
    final tab = state.tabOf(id);
    if (tab == null || !tab.isSplit) return;
    _set(
      state.copyWith(
        tabs: _replaceTab(
          tab.copyWith(zoomedId: tab.zoomedId == id ? null : id, focusedId: id),
        ),
      ),
    );
  }

  /// Renames workspace [tabId]; an empty name goes back to the default.
  void rename(String tabId, String name) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    final trimmed = name.trim();
    _set(
      state.copyWith(
        tabs: _replaceTab(tab.copyWith(name: trimmed.isEmpty ? null : trimmed)),
      ),
    );
  }

  void toggleBroadcast(String tabId) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    _set(
      state.copyWith(
        tabs: _replaceTab(tab.copyWith(broadcast: !tab.broadcast)),
      ),
    );
  }

  /// Moves pane [id] next to pane [targetId] (possibly in another tab).
  /// [DropSide.center] swaps the two. Returns false if the target
  /// workspace is full.
  bool movePaneTo(String id, String targetId, DropSide side) {
    if (id == targetId) return true;
    final from = state.tabOf(id);
    final to = state.tabOf(targetId);
    if (from == null || to == null) return false;

    if (from.id == to.id) {
      _set(
        state.copyWith(
          tabs: _replaceTab(
            from.copyWith(
              layout: movePane(from.layout, id, targetId, side),
              focusedId: id,
              zoomedId: null,
            ),
          ),
          activeTabId: from.id,
        ),
      );
      return true;
    }

    if (side == DropSide.center) {
      // Swap across tabs.
      final tabs = state.tabs.map((t) {
        if (t.id == from.id) {
          return t.copyWith(
            layout: replacePane(t.layout, id, targetId),
            focusedId: t.focusedId == id ? targetId : t.focusedId,
            zoomedId: null,
          );
        }
        if (t.id == to.id) {
          return t.copyWith(
            layout: replacePane(t.layout, targetId, id),
            focusedId: id,
            zoomedId: null,
          );
        }
        return t;
      }).toList();
      _set(state.copyWith(tabs: tabs, activeTabId: to.id));
      return true;
    }

    if (to.paneIds.length >= maxPanes) return false;
    final tabs = <WorkspaceTab>[];
    for (final t in state.tabs) {
      if (t.id == from.id) {
        final rest = removePane(t.layout, id);
        if (rest == null) continue; // the moved pane was the whole tab
        tabs.add(
          t.copyWith(
            layout: rest,
            focusedId: t.focusedId == id ? rest.panes.first : t.focusedId,
            zoomedId: t.zoomedId == id ? null : t.zoomedId,
          ),
        );
      } else if (t.id == to.id) {
        tabs.add(
          t.copyWith(
            layout: insertPane(t.layout, targetId, id, side),
            focusedId: id,
            zoomedId: null,
          ),
        );
      } else {
        tabs.add(t);
      }
    }
    _set(state.copyWith(tabs: tabs, activeTabId: to.id));
    return true;
  }

  /// Drops a whole tab onto pane [targetId] of another tab: its panes
  /// join that workspace on [side]. Returns false if it would not fit.
  bool mergeTabInto(String tabId, String targetId, DropSide side) {
    final source = state.tabById(tabId);
    final target = state.tabOf(targetId);
    if (source == null || target == null || source.id == target.id) {
      return false;
    }
    if (!source.isSplit) {
      return movePaneTo(source.focusedId, targetId, side);
    }
    if (side == DropSide.center) return false;
    if (source.paneIds.length + target.paneIds.length > maxPanes) {
      return false;
    }
    final tabs = [
      for (final t in state.tabs)
        if (t.id == target.id)
          t.copyWith(
            layout: insertLayout(t.layout, targetId, source.layout, side),
            focusedId: source.focusedId,
            zoomedId: null,
            broadcast: t.broadcast,
          )
        else if (t.id != source.id)
          t,
    ];
    _set(state.copyWith(tabs: tabs, activeTabId: target.id));
    return true;
  }

  /// Takes pane [id] out of its workspace into a tab of its own, placed
  /// at [index] (default: after its old tab).
  void detachToTab(String id, {int? index}) {
    final from = state.tabOf(id);
    if (from == null) return;
    if (!from.isSplit) {
      if (index != null) moveTab(from.id, index);
      return;
    }
    final rest = removePane(from.layout, id)!;
    final tab = WorkspaceTab(
      id: Host.newId(),
      layout: PaneNode(id),
      focusedId: id,
    );
    final tabs = [
      for (final t in state.tabs)
        if (t.id == from.id)
          t.copyWith(
            layout: rest,
            focusedId: t.focusedId == id ? rest.panes.first : t.focusedId,
            zoomedId: t.zoomedId == id ? null : t.zoomedId,
          )
        else
          t,
    ];
    final at = (index ?? tabs.indexWhere((t) => t.id == from.id) + 1).clamp(
      0,
      tabs.length,
    );
    tabs.insert(at, tab);
    _set(state.copyWith(tabs: tabs, activeTabId: tab.id));
  }

  /// Moves tab [tabId] to position [index] (as in the strip before the
  /// move; dropping right of itself counts its own slot).
  void moveTab(String tabId, int index) {
    final tabs = [...state.tabs];
    final from = tabs.indexWhere((t) => t.id == tabId);
    if (from < 0) return;
    final tab = tabs.removeAt(from);
    var to = index > from ? index - 1 : index;
    to = to.clamp(0, tabs.length);
    tabs.insert(to, tab);
    _set(state.copyWith(tabs: tabs, activeTabId: tabId));
  }

  List<WorkspaceTab> _replaceTab(WorkspaceTab tab) => [
    for (final t in state.tabs) t.id == tab.id ? tab : t,
  ];

  void _set(SessionsState next) {
    state = _numbered(next);
    _syncBroadcast();
  }

  /// Gives each workspace that has become split a number for its default
  /// name ("Workspace 1"), the smallest one not in use.
  SessionsState _numbered(SessionsState s) {
    // A tab back to one pane gives its number up.
    if (!s.tabs.any((t) => t.isSplit == (t.number == null))) {
      return s;
    }
    final used = {
      for (final t in s.tabs)
        if (t.number != null && t.isSplit) t.number!,
    };
    final tabs = [
      for (final t in s.tabs)
        if (t.isSplit && t.number == null)
          t.copyWith(number: _nextNumber(used))
        else if (!t.isSplit && t.number != null)
          t.copyWith(number: null)
        else
          t,
    ];
    return s.copyWith(tabs: tabs);
  }

  static int _nextNumber(Set<int> used) {
    var n = 1;
    while (used.contains(n)) {
      n++;
    }
    used.add(n);
    return n;
  }

  /// Wires typing in each pane of a broadcasting tab to its other panes.
  void _syncBroadcast() {
    final mirrors = <String, List<TerminalSession>>{};
    for (final t in state.tabs) {
      if (!t.broadcast) continue;
      final members = [for (final id in t.paneIds) ?state.session(id)];
      for (final s in members) {
        mirrors[s.id] = [
          for (final o in members)
            if (o != s) o,
        ];
      }
    }
    for (final s in state.sessions) {
      final others = mirrors[s.id];
      s.onUserInput = others == null
          ? null
          : (data) {
              for (final o in others) {
                o.sendInput(data);
              }
            };
    }
  }
}

final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(
  SessionsNotifier.new,
);
