import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../terminal/sessions_providers.dart';
import '../terminal/terminal_session.dart';
import 'remote_fs.dart';

enum FileSort { name, modified, size, kind }

class FileBrowserState {
  const FileBrowserState({
    this.path,
    this.listings = const {},
    this.selected,
    this.back = const [],
    this.forward = const [],
    this.follow = true,
    this.sort = FileSort.name,
    this.ascending = true,
    this.locating = false,
    this.refreshing = false,
    this.error,
  });

  /// The folder shown (null until the terminal's folder is found).
  final String? path;

  /// Folder contents by folder path (the current one and, for the column
  /// view, its ancestors).
  final Map<String, AsyncValue<List<RemoteEntry>>> listings;

  /// Path of the selected entry.
  final String? selected;

  final List<String> back;
  final List<String> forward;

  /// Go where the terminal's shell goes (after each command).
  final bool follow;
  final FileSort sort;
  final bool ascending;

  /// Looking up the terminal's folder.
  final bool locating;

  /// Reloading the shown folders (the refresh button spins).
  final bool refreshing;

  /// Why nothing can be shown (e.g. not connected).
  final String? error;

  AsyncValue<List<RemoteEntry>>? get current =>
      path == null ? null : listings[path];

  FileBrowserState copyWith({
    String? path,
    Map<String, AsyncValue<List<RemoteEntry>>>? listings,
    Object? selected = _keep,
    List<String>? back,
    List<String>? forward,
    bool? follow,
    FileSort? sort,
    bool? ascending,
    bool? locating,
    bool? refreshing,
    Object? error = _keep,
  }) => FileBrowserState(
    path: path ?? this.path,
    listings: listings ?? this.listings,
    selected: identical(selected, _keep) ? this.selected : selected as String?,
    back: back ?? this.back,
    forward: forward ?? this.forward,
    follow: follow ?? this.follow,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    locating: locating ?? this.locating,
    refreshing: refreshing ?? this.refreshing,
    error: identical(error, _keep) ? this.error : error as String?,
  );

  static const _keep = Object();
}

/// The file browser of one terminal tab (pane): where it is, what it
/// has loaded, and its history. Kept while the app runs, so each pane
/// remembers its place.
class FileBrowserNotifier extends Notifier<FileBrowserState> {
  FileBrowserNotifier(this.sessionId);

  final String sessionId;
  Timer? _followTimer;
  final _previews = <String, Future<Uint8List>>{};

  TerminalSession? get _session =>
      ref.read(sessionsProvider).session(sessionId);

  @override
  FileBrowserState build() {
    // Read now: refs can't be used while disposing.
    final session = _session;
    ref.onDispose(() {
      _followTimer?.cancel();
      if (session != null && session.onCommandEntered == _onCommandEntered) {
        session.onCommandEntered = null;
      }
    });
    session?.onCommandEntered = _onCommandEntered;
    return const FileBrowserState();
  }

  /// First look: go to the terminal's folder.
  Future<void> start() async {
    if (state.path != null || state.locating) return;
    await locate();
  }

  /// Goes to the folder the terminal's shell is in (home if unknown).
  Future<void> locate() async {
    final session = _session;
    if (session == null) return;
    if (session.status != SessionStatus.connected) {
      state = state.copyWith(error: 'not connected');
      return;
    }
    state = state.copyWith(locating: true, error: null);
    try {
      final cwd = await session.shellCwd();
      final path = cwd ?? await (await session.remoteFs()).home();
      if (!ref.mounted) return;
      state = state.copyWith(locating: false);
      if (path != state.path) await go(path);
    } catch (e) {
      log.warn('files', 'Could not open SFTP: $e');
      if (ref.mounted) {
        state = state.copyWith(locating: false, error: '$e');
      }
    }
  }

  void _onCommandEntered() {
    if (!state.follow || state.path == null) return;
    // Give the command a moment to run (e.g. `cd`), then look again.
    _followTimer?.cancel();
    _followTimer = Timer(const Duration(milliseconds: 700), () async {
      final cwd = await _session?.shellCwd();
      if (!ref.mounted || cwd == null) return;
      if (cwd != state.path) {
        await go(cwd);
      } else {
        // Same folder: check for changes without disturbing the view.
        await load(cwd, force: true, quiet: true);
      }
    });
  }

  void setFollow(bool on) {
    state = state.copyWith(follow: on);
    if (on) locate();
  }

  Future<void> go(String path, {bool record = true}) async {
    final from = state.path;
    state = state.copyWith(
      path: path,
      selected: null,
      back: record && from != null && from != path
          ? [...state.back, from]
          : state.back,
      forward: record ? const [] : state.forward,
      error: null,
    );
    await load(path);
  }

  Future<void> goBack() async {
    if (state.back.isEmpty) return;
    final to = state.back.last;
    state = state.copyWith(
      back: state.back.sublist(0, state.back.length - 1),
      forward: [?state.path, ...state.forward],
    );
    await go(to, record: false);
  }

  Future<void> goForward() async {
    if (state.forward.isEmpty) return;
    final to = state.forward.first;
    state = state.copyWith(
      forward: state.forward.sublist(1),
      back: [...state.back, ?state.path],
    );
    await go(to, record: false);
  }

  Future<void> up() async {
    final path = state.path;
    if (path == null || path == '/') return;
    final from = path;
    await go(parentPath(path));
    state = state.copyWith(selected: from);
  }

  /// Reloads the shown folders in place (what's shown stays until the
  /// new listing is in, and only changes if the folder did).
  Future<void> refresh() async {
    final path = state.path;
    if (path == null) return;
    _previews.clear();
    state = state.copyWith(refreshing: true);
    try {
      await Future.wait([
        for (final dir in state.listings.keys.toList())
          load(dir, force: true, quiet: state.listings[dir]?.hasValue ?? false),
      ]);
    } finally {
      if (ref.mounted) state = state.copyWith(refreshing: false);
    }
  }

  /// Loads folder [dir] (if not loaded yet, or [force]). [quiet] keeps the
  /// current listing on screen meanwhile (no spinner), replaces it only
  /// if something changed, and keeps it if loading fails.
  Future<void> load(
    String dir, {
    bool force = false,
    bool quiet = false,
  }) async {
    final have = state.listings[dir];
    if (!force && have != null && (have.hasValue || have.isLoading)) return;
    final session = _session;
    if (session == null) return;
    final old = have?.value;
    if (!quiet || old == null) {
      state = state.copyWith(
        listings: {...state.listings, dir: const AsyncLoading()},
      );
    }
    try {
      final fs = await session.remoteFs();
      final list = await fs.list(dir);
      if (!ref.mounted) return;
      if (quiet && old != null && sameEntries(old, list)) return;
      state = state.copyWith(
        listings: {...state.listings, dir: AsyncData(list)},
      );
    } catch (e, st) {
      if (!ref.mounted || (quiet && old != null)) return;
      state = state.copyWith(
        listings: {...state.listings, dir: AsyncError(e, st)},
      );
    }
  }

  void select(String? path) => state = state.copyWith(selected: path);

  void sortBy(FileSort sort) => state = state.copyWith(
    sort: sort,
    ascending: state.sort == sort ? !state.ascending : true,
  );

  /// The start of file [path] (for previews), cached.
  Future<Uint8List> preview(String path, {int maxBytes = 1 << 20}) {
    final session = _session;
    if (session == null) return Future.error(StateError('closed'));
    return _previews[path] ??=
        session.remoteFs().then((fs) => fs.read(path, maxBytes: maxBytes))
          ..catchError((Object _) {
            _previews.remove(path);
            return Uint8List(0);
          }).ignore();
  }

  /// Types `cd <folder>` into the terminal (the user's shell goes there).
  void cdInTerminal(String folder) =>
      _session?.sendInput(_session!.cdCommand(folder));
}

final fileBrowserProvider =
    NotifierProvider.family<FileBrowserNotifier, FileBrowserState, String>(
      FileBrowserNotifier.new,
    );

/// Whether two listings show the same thing.
bool sameEntries(List<RemoteEntry> a, List<RemoteEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.name != y.name ||
        x.isDir != y.isDir ||
        x.size != y.size ||
        x.modified != y.modified ||
        x.mode != y.mode) {
      return false;
    }
  }
  return true;
}

/// [entries] sorted: folders first, then by [sort].
List<RemoteEntry> sortEntries(
  List<RemoteEntry> entries,
  FileSort sort,
  bool ascending, {
  required bool showHidden,
  required String Function(RemoteEntry) kindOf,
}) {
  final list = [
    for (final e in entries)
      if (showHidden || !e.isHidden) e,
  ];
  int byName(RemoteEntry a, RemoteEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    final c = switch (sort) {
      FileSort.name => byName(a, b),
      FileSort.modified => (a.modified ?? DateTime(0)).compareTo(
        b.modified ?? DateTime(0),
      ),
      FileSort.size => (a.size ?? 0).compareTo(b.size ?? 0),
      FileSort.kind => kindOf(a).compareTo(kindOf(b)),
    };
    final r = c == 0 ? byName(a, b) : c;
    return ascending ? r : -r;
  });
  return list;
}
