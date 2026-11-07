import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import '../keys/keys_providers.dart';
import 'known_hosts.dart';
import 'session_prompts.dart';
import 'terminal_session.dart';

final knownHostsProvider = Provider<KnownHostsStore>(
  (ref) => KnownHostsStore(dataDir: ref.watch(dataDirProvider)),
);

final sessionPromptsProvider = Provider<SessionPrompts>(
  (ref) => DialogSessionPrompts(rootNavigatorKey),
);

class SessionsState {
  const SessionsState({this.sessions = const [], this.activeId});

  final List<TerminalSession> sessions;
  final String? activeId;

  TerminalSession? get active {
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }
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

  TerminalSession open(Host host) {
    final session = TerminalSession(
      host: host,
      repository: ref.read(hostRepositoryProvider),
      knownHosts: ref.read(knownHostsProvider),
      prompts: ref.read(sessionPromptsProvider),
      keys: ref.read(keyRepositoryProvider),
    );
    _open.add(session);
    state = SessionsState(
      sessions: [...state.sessions, session],
      activeId: session.id,
    );
    session.connect();
    return session;
  }

  void activate(String id) =>
      state = SessionsState(sessions: state.sessions, activeId: id);

  void close(String id) {
    final sessions = [...state.sessions];
    final index = sessions.indexWhere((s) => s.id == id);
    if (index < 0) return;
    final removed = sessions.removeAt(index);

    var activeId = state.activeId;
    if (activeId == id) {
      activeId = sessions.isEmpty
          ? null
          : sessions[index.clamp(0, sessions.length - 1)].id;
    }
    state = SessionsState(sessions: sessions, activeId: activeId);
    _open.remove(removed);
    removed.dispose();
  }
}

final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(
  SessionsNotifier.new,
);
