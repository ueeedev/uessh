import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import '../terminal/terminal_session.dart';
import 'file_browser.dart';
import 'remote_fs.dart';
import 'uploads.dart';
import '../../widgets/toasts.dart';

// ---------------------------------------------------------------------------
// Kinds and icons

enum FileKind {
  folder,
  image,
  text,
  code,
  archive,
  video,
  audio,
  pdf,
  document,
  executable,
  file,
}

const _ext = <FileKind, Set<String>>{
  FileKind.image: {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico', 'heic', 'tif',
    'tiff', //
  },
  FileKind.code: {
    'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'go', 'rs', 'c', 'h', 'cc', 'cpp',
    'hpp', 'java', 'kt', 'rb', 'php', 'sh', 'bash', 'zsh', 'fish', 'swift',
    'lua', 'pl', 'sql', 'html', 'htm', 'css', 'scss', 'vue', 'json', 'yaml',
    'yml', 'toml', 'xml', 'ini', 'conf', 'cfg', 'env', 'service', 'socket',
    'timer', 'properties', 'gradle', 'mk', 'cmake', 'tf', 'nginx', //
  },
  FileKind.text: {'txt', 'md', 'log', 'csv', 'tsv', 'rst', 'out', 'err'},
  FileKind.archive: {
    'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar', 'zst', 'deb', 'rpm',
    'jar', 'war', 'iso', //
  },
  FileKind.video: {'mp4', 'mkv', 'mov', 'avi', 'webm', 'flv', 'm4v'},
  FileKind.audio: {'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'opus'},
  FileKind.pdf: {'pdf'},
  FileKind.document: {
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'rtf',
  },
};

/// Names without an extension that are still text (configs, scripts).
const _textNames = {
  'dockerfile', 'makefile', 'readme', 'license', 'hosts', 'fstab', 'passwd',
  'group', 'crontab', 'authorized_keys', 'known_hosts', 'config', 'profile',
  'bashrc', '.bashrc', '.profile', '.zshrc', '.vimrc', '.gitconfig',
  '.gitignore', '.env', //
};

FileKind kindOf(RemoteEntry e) {
  if (e.isDir) return FileKind.folder;
  final ext = e.extension;
  for (final k in _ext.entries) {
    if (k.value.contains(ext)) return k.key;
  }
  if (_textNames.contains(e.name.toLowerCase())) return FileKind.text;
  if (e.isExecutable) return FileKind.executable;
  return FileKind.file;
}

String kindLabel(AppLocalizations l, RemoteEntry e) {
  final label = switch (kindOf(e)) {
    FileKind.folder => l.kindFolder,
    FileKind.image => l.kindImage,
    FileKind.text => l.kindText,
    FileKind.code => l.kindCode,
    FileKind.archive => l.kindArchive,
    FileKind.video => l.kindVideo,
    FileKind.audio => l.kindAudio,
    FileKind.pdf => l.kindPdf,
    FileKind.document => l.kindDocument,
    FileKind.executable => l.kindExecutable,
    FileKind.file => l.kindFile,
  };
  return e.isLink ? '$label (${l.kindLink})' : label;
}

/// Icon for [e], with a little arrow badge for links.
class FileIcon extends StatelessWidget {
  const FileIcon(this.entry, {super.key, this.size = 20});

  final RemoteEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final (IconData icon, Color color) = switch (kindOf(entry)) {
      FileKind.folder => (Icons.folder, const Color(0xFF4A9EF0)),
      FileKind.image => (Icons.image, const Color(0xFF34A853)),
      FileKind.text => (Icons.description, scheme.onSurfaceVariant),
      FileKind.code => (Icons.code, const Color(0xFF7E57C2)),
      FileKind.archive => (Icons.folder_zip, const Color(0xFFB7791F)),
      FileKind.video => (Icons.movie, const Color(0xFFE8710A)),
      FileKind.audio => (Icons.audio_file, const Color(0xFFD81B60)),
      FileKind.pdf => (Icons.picture_as_pdf, const Color(0xFFD93025)),
      FileKind.document => (Icons.article, const Color(0xFF1A73E8)),
      FileKind.executable => (Icons.terminal, scheme.onSurface),
      FileKind.file => (Icons.insert_drive_file, scheme.outline),
    };
    final base = Icon(
      icon,
      size: size,
      color: dark && kindOf(entry) == FileKind.folder
          ? const Color(0xFF6CB2F7)
          : color,
    );
    if (!entry.isLink) return base;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          left: -1,
          bottom: -1,
          child: Icon(
            Icons.shortcut,
            size: size * 0.45,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

String formatSize(int? bytes) {
  if (bytes == null) return '--';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return u == 0
      ? '$bytes B'
      : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[u]}';
}

String formatModified(DateTime? t) =>
    t == null ? '--' : DateFormat('yyyy-MM-dd HH:mm').format(t);

String formatMode(int? mode) {
  if (mode == null) return '--';
  const chars = 'rwxrwxrwx';
  final b = StringBuffer();
  for (var i = 0; i < 9; i++) {
    b.write((mode & (1 << (8 - i))) != 0 ? chars[i] : '-');
  }
  return '${b.toString()}  (${(mode & 0x1ff).toRadixString(8).padLeft(3, '0')})';
}

// ---------------------------------------------------------------------------
// Panel

/// The file browser below the terminal, for the focused pane's server.
class FilesPanel extends ConsumerStatefulWidget {
  const FilesPanel({super.key, required this.session, required this.onClose});

  final TerminalSession session;
  final VoidCallback onClose;

  @override
  ConsumerState<FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends ConsumerState<FilesPanel> {
  FileBrowserNotifier get _n =>
      ref.read(fileBrowserProvider(widget.session.id).notifier);

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _n.start();
    });
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  // Connected later (or again): look again.
  void _onSession() {
    if (!mounted) return;
    final s = ref.read(fileBrowserProvider(widget.session.id));
    if (widget.session.status == SessionStatus.connected &&
        (s.path == null || s.error != null)) {
      _n.locate();
    }
  }

  Future<void> _open(RemoteEntry e) async {
    if (e.isDir) {
      await _n.go(e.path);
    } else {
      _n.select(e.path);
      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(
          entry: e,
          sessionId: widget.session.id,
          onDownload: () => _download(e),
        ),
      );
    }
  }

  Future<void> _download(RemoteEntry e) async {
    final l = context.l10n;
    final location = await getSaveLocation(suggestedName: e.name);
    if (location == null) return;
    // One card: "downloading…" turns into the result.
    final id = showToast(l.filesDownloading(e.name), duration: null);
    try {
      final fs = await widget.session.remoteFs();
      await fs.download(e.path, File(location.path));
      showToast(
        l.filesDownloaded(location.path),
        kind: ToastKind.success,
        id: id,
      );
    } catch (err) {
      showToast(l.filesError('$err'), kind: ToastKind.error, id: id);
    }
  }

  Future<void> _menu(RemoteEntry e, Offset at) async {
    final l = context.l10n;
    _n.select(e.path);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'open', child: Text(l.filesOpen)),
        if (e.isDir) PopupMenuItem(value: 'cd', child: Text(l.filesCdHere)),
        if (e.isDir)
          PopupMenuItem(value: 'upload', child: Text(l.filesUploadHere)),
        PopupMenuItem(value: 'copy', child: Text(l.filesCopyPath)),
        if (!e.isDir)
          PopupMenuItem(value: 'download', child: Text(l.filesDownload)),
      ],
    );
    switch (action) {
      case 'open':
        await _open(e);
      case 'cd':
        _n.cdInTerminal(e.path);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e.path));
      case 'download':
        await _download(e);
      case 'upload':
        if (mounted) await pickAndUpload(context, ref, widget.session, e.path);
    }
  }

  /// Right-click on empty space: upload into the shown folder.
  Future<void> _folderMenu(Offset at) async {
    final path = ref.read(fileBrowserProvider(widget.session.id)).path;
    if (path == null) return;
    final l = context.l10n;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'upload', child: Text(l.filesUpload)),
        PopupMenuItem(value: 'cd', child: Text(l.filesCdHere)),
        PopupMenuItem(value: 'copy', child: Text(l.filesCopyPath)),
        PopupMenuItem(value: 'refresh', child: Text(l.filesRefresh)),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'upload':
        await pickAndUpload(context, ref, widget.session, path);
      case 'cd':
        _n.cdInTerminal(path);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: path));
      case 'refresh':
        await _n.refresh();
    }
  }

  // --- Dropping files from the computer ---

  final _bodyKey = GlobalKey();

  /// Where a drop would go (null: nothing is being dragged over).
  String? _dropTarget;

  /// The folder under [global] in the shown items, else the shown folder.
  String? _folderAt(Offset global) {
    final current = ref.read(fileBrowserProvider(widget.session.id)).path;
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return current;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData) {
        final data = target.metaData;
        if (data is RemoteEntry && data.isDir) return data.path;
      }
    }
    return current;
  }

  void _dragOver(Offset global) {
    final to = _folderAt(global);
    if (to != _dropTarget) setState(() => _dropTarget = to);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(fileBrowserProvider(widget.session.id));
    final settings = ref.watch(settingsProvider);
    final mode = settings.fileViewMode;

    List<RemoteEntry> sorted(List<RemoteEntry> list) => sortEntries(
      list,
      state.sort,
      state.ascending,
      showHidden: settings.showHiddenFiles,
      kindOf: (e) => kindLabel(l, e),
    );

    final actions = _ItemActions(select: _n.select, open: _open, menu: _menu);

    Widget body;
    if (widget.session.status != SessionStatus.connected) {
      body = _Message(icon: Icons.link_off, text: l.filesNotConnected);
    } else if (state.error != null) {
      body = _Message(
        icon: Icons.error_outline,
        text: l.filesError(state.error!),
      );
    } else if (state.path == null) {
      body = _Message(
        icon: Icons.manage_search,
        text: l.filesLocating,
        busy: true,
      );
    } else if (mode == FileViewMode.columns) {
      body = _ColumnsView(
        state: state,
        sessionId: widget.session.id,
        sorted: sorted,
        actions: actions,
      );
    } else {
      body = switch (state.current) {
        null ||
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => _Message(
          icon: Icons.error_outline,
          text: l.filesError('$error'),
        ),
        AsyncData(:final value) => () {
          final items = sorted(value);
          if (items.isEmpty) {
            return _Message(icon: Icons.folder_open, text: l.filesEmpty);
          }
          return switch (mode) {
            FileViewMode.icons => _IconsView(
              items: items,
              selected: state.selected,
              actions: actions,
            ),
            FileViewMode.list => _ListView(
              items: items,
              state: state,
              actions: actions,
              onSort: _n.sortBy,
            ),
            _ => _GalleryView(
              items: items,
              selected: state.selected,
              sessionId: widget.session.id,
              actions: actions,
            ),
          };
        }(),
      };
    }

    return Material(
      key: const ValueKey('files-panel'),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            state: state,
            mode: mode,
            showHidden: settings.showHiddenFiles,
            onClose: widget.onClose,
            notifier: _n,
            onUpload: () {
              final path = state.path;
              if (path != null) {
                pickAndUpload(context, ref, widget.session, path);
              }
            },
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: DropTarget(
              enable: widget.session.status == SessionStatus.connected,
              onDragEntered: (d) => _dragOver(d.globalPosition),
              onDragUpdated: (d) => _dragOver(d.globalPosition),
              onDragExited: (_) => setState(() => _dropTarget = null),
              onDragDone: (d) {
                final to = _folderAt(d.globalPosition);
                setState(() => _dropTarget = null);
                if (to != null) {
                  uploadTo(
                    context,
                    ref,
                    widget.session,
                    to,
                    dropSources(d.files),
                  );
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    key: _bodyKey,
                    behavior: HitTestBehavior.opaque,
                    // Items take their own right-clicks; this is the rest.
                    onSecondaryTapDown: (d) => _folderMenu(d.globalPosition),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: KeyedSubtree(
                        key: ValueKey('${mode.name}-${state.path}'),
                        child: body,
                      ),
                    ),
                  ),
                  if (_dropTarget != null)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: DropOverlay(
                        label: l.dropToUpload(_dropTarget!),
                        radius: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemActions {
  const _ItemActions({
    required this.select,
    required this.open,
    required this.menu,
  });

  final void Function(String? path) select;
  final Future<void> Function(RemoteEntry e) open;
  final Future<void> Function(RemoteEntry e, Offset at) menu;

  /// Click selects, double-click opens, right-click shows the menu. With
  /// [clickOpensFolders] (column view), a click on a folder opens it.
  Widget wrap(RemoteEntry e, Widget child, {bool clickOpensFolders = false}) =>
      MetaData(
        // Lets a file drop find the folder under the pointer.
        metaData: e,
        behavior: HitTestBehavior.translucent,
        child: _Clickable(
          key: ValueKey('file-${e.path}'),
          onClick: () =>
              clickOpensFolders && e.isDir ? open(e) : select(e.path),
          onDoubleClick: () => open(e),
          onSecondary: (at) => menu(e, at),
          child: child,
        ),
      );
}

/// Click / double-click / right-click without the wait a double-tap
/// recognizer adds to every click: a click acts at once, and a second one
/// soon after (by the pointer's own timestamps) counts as a double-click.
class _Clickable extends StatefulWidget {
  const _Clickable({
    super.key,
    required this.onClick,
    required this.onDoubleClick,
    required this.onSecondary,
    required this.child,
  });

  final VoidCallback onClick;
  final VoidCallback onDoubleClick;
  final ValueChanged<Offset> onSecondary;
  final Widget child;

  static const doubleClickTime = Duration(milliseconds: 400);

  @override
  State<_Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<_Clickable> {
  Duration? _downAt;
  Duration? _lastClick;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _downAt = e.timeStamp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final now = _downAt, last = _lastClick;
          if (now != null &&
              last != null &&
              now - last < _Clickable.doubleClickTime) {
            _lastClick = null;
            widget.onDoubleClick();
          } else {
            _lastClick = now;
            widget.onClick();
          }
        },
        onSecondaryTapDown: (d) => widget.onSecondary(d.globalPosition),
        child: widget.child,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.busy = false});

  final IconData icon;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, size: 36, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.state,
    required this.mode,
    required this.showHidden,
    required this.onClose,
    required this.notifier,
    required this.onUpload,
  });

  final VoidCallback onUpload;
  final FileBrowserState state;
  final FileViewMode mode;
  final bool showHidden;
  final VoidCallback onClose;
  final FileBrowserNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.read(settingsProvider.notifier);

    Widget button(
      String tip,
      IconData icon,
      VoidCallback? onTap, {
      bool selected = false,
      Key? key,
    }) => IconButton(
      key: key,
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      isSelected: selected,
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
            )
          : null,
      icon: Icon(icon),
      onPressed: onTap,
    );

    final count = state.current?.value
        ?.where((e) => showHidden || !e.isHidden)
        .length;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 6),
          button(
            l.filesBack,
            Icons.chevron_left,
            state.back.isEmpty ? null : notifier.goBack,
            key: const ValueKey('files-back'),
          ),
          button(
            l.filesForward,
            Icons.chevron_right,
            state.forward.isEmpty ? null : notifier.goForward,
            key: const ValueKey('files-forward'),
          ),
          button(
            l.filesUp,
            Icons.arrow_upward,
            state.path == null || state.path == '/' ? null : notifier.up,
            key: const ValueKey('files-up'),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: state.path == null
                ? const SizedBox.shrink()
                : _Breadcrumb(path: state.path!, onGo: notifier.go),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l.filesItems(count),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          button(
            l.filesFollow,
            Icons.my_location,
            () => notifier.setFollow(!state.follow),
            selected: state.follow,
            key: const ValueKey('files-follow'),
          ),
          button(
            showHidden ? l.filesHideHidden : l.filesShowHidden,
            showHidden ? Icons.visibility : Icons.visibility_off_outlined,
            () => settings.update(
              (s) => s.copyWith(showHiddenFiles: !showHidden),
            ),
            selected: showHidden,
            key: const ValueKey('files-hidden'),
          ),
          button(
            l.filesUpload,
            Icons.upload,
            state.path == null ? null : onUpload,
            key: const ValueKey('files-upload'),
          ),
          state.refreshing
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : button(
                  l.filesRefresh,
                  Icons.refresh,
                  notifier.refresh,
                  key: const ValueKey('files-refresh'),
                ),
          const SizedBox(width: 6),
          // View modes, as in the Finder.
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                for (final (m, icon, tip) in [
                  (FileViewMode.icons, Icons.grid_view, l.viewIcons),
                  (FileViewMode.list, Icons.view_list, l.viewList),
                  (FileViewMode.columns, Icons.view_column, l.viewColumns),
                  (FileViewMode.gallery, Icons.view_carousel, l.viewGallery),
                ])
                  button(
                    tip,
                    icon,
                    () => settings.update((s) => s.copyWith(fileViewMode: m)),
                    selected: mode == m,
                    key: ValueKey('view-${m.name}'),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          button(l.filesHide, Icons.close, onClose),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// The path as clickable folders: / › var › log.
class _Breadcrumb extends StatefulWidget {
  const _Breadcrumb({required this.path, required this.onGo});

  final String path;
  final Future<void> Function(String) onGo;

  @override
  State<_Breadcrumb> createState() => _BreadcrumbState();
}

class _BreadcrumbState extends State<_Breadcrumb> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void didUpdateWidget(_Breadcrumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = ancestorsOf(widget.path);
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            TextButton(
              key: ValueKey('crumb-${parts[i]}'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
                foregroundColor: i == parts.length - 1
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
              onPressed: () => widget.onGo(parts[i]),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i == 0) ...[
                    Icon(Icons.dns_outlined, size: 15, color: scheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    i == 0 ? '/' : parts[i].split('/').last,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: i == parts.length - 1
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Views

class _IconsView extends StatelessWidget {
  const _IconsView({
    required this.items,
    required this.selected,
    required this.actions,
  });

  final List<RemoteEntry> items;
  final String? selected;
  final _ItemActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: () => actions.select(null),
      child: GridView.builder(
        key: const ValueKey('files-icons'),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 104,
          mainAxisExtent: 96,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final e = items[i];
          final sel = e.path == selected;
          return actions.wrap(
            e,
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              decoration: BoxDecoration(
                color: sel ? scheme.secondaryContainer : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  FileIcon(e, size: 44),
                  const SizedBox(height: 6),
                  Text(
                    e.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: sel ? scheme.onSecondaryContainer : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.items,
    required this.state,
    required this.actions,
    required this.onSort,
  });

  final List<RemoteEntry> items;
  final FileBrowserState state;
  final _ItemActions actions;
  final void Function(FileSort) onSort;

  static const _dateWidth = 150.0;
  static const _sizeWidth = 90.0;
  static const _kindWidth = 130.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget header(
      String label,
      FileSort sort, {
      double? width,
      bool end = false,
    }) {
      final active = state.sort == sort;
      final cell = InkWell(
        key: ValueKey('sort-${sort.name}'),
        onTap: () => onSort(sort),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: end
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w600 : null,
                ),
              ),
              if (active)
                Icon(
                  state.ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 16,
                  color: scheme.primary,
                ),
            ],
          ),
        ),
      );
      return width == null
          ? Expanded(child: cell)
          : SizedBox(width: width, child: cell);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              header(l.colName, FileSort.name),
              header(l.colModified, FileSort.modified, width: _dateWidth),
              header(l.colSize, FileSort.size, width: _sizeWidth, end: true),
              header(l.colKind, FileSort.kind, width: _kindWidth),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('files-list'),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            itemExtent: 30,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              final sel = e.path == state.selected;
              return actions.wrap(
                e,
                Container(
                  decoration: BoxDecoration(
                    color: sel
                        ? scheme.secondaryContainer
                        : i.isOdd
                        ? scheme.onSurface.withValues(alpha: 0.03)
                        : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              FileIcon(e, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _dateWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(formatModified(e.modified), style: small),
                        ),
                      ),
                      SizedBox(
                        width: _sizeWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            e.isDir ? '--' : formatSize(e.size),
                            textAlign: TextAlign.end,
                            style: small,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _kindWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            kindLabel(l, e),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
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
  }
}

/// Finder-style columns: one per folder from / down to the current one,
/// then a preview of the selected file.
class _ColumnsView extends ConsumerStatefulWidget {
  const _ColumnsView({
    required this.state,
    required this.sessionId,
    required this.sorted,
    required this.actions,
  });

  final FileBrowserState state;
  final String sessionId;
  final List<RemoteEntry> Function(List<RemoteEntry>) sorted;
  final _ItemActions actions;

  @override
  ConsumerState<_ColumnsView> createState() => _ColumnsViewState();
}

class _ColumnsViewState extends ConsumerState<_ColumnsView> {
  final _scroll = ScrollController();
  static const _width = 230.0;

  @override
  void initState() {
    super.initState();
    _loadAndScroll();
  }

  @override
  void didUpdateWidget(_ColumnsView old) {
    super.didUpdateWidget(old);
    if (old.state.path != widget.state.path ||
        old.state.selected != widget.state.selected) {
      _loadAndScroll();
    }
  }

  void _loadAndScroll() {
    // After this frame: state can't change while widgets are building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = ref.read(fileBrowserProvider(widget.sessionId).notifier);
      for (final dir in ancestorsOf(widget.state.path!)) {
        n.load(dir);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = widget.state;
    final dirs = ancestorsOf(state.path!);
    final selectedFile = () {
      final list = state.current?.value;
      if (list == null) return null;
      for (final e in list) {
        if (e.path == state.selected && !e.isDir) return e;
      }
      return null;
    }();

    Widget column(int i) {
      final dir = dirs[i];
      final next = i + 1 < dirs.length ? dirs[i + 1] : state.selected;
      final listing = state.listings[dir];
      return Container(
        key: ValueKey('column-$dir'),
        width: _width,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: switch (listing) {
          AsyncData(:final value) => ListView(
            padding: const EdgeInsets.all(4),
            children: [
              for (final e in widget.sorted(value))
                widget.actions.wrap(
                  e,
                  clickOpensFolders: true,
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: e.path == next
                          ? (i + 1 < dirs.length
                                ? scheme.surfaceContainerHighest
                                : scheme.secondaryContainer)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        FileIcon(e, size: 17),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (e.isDir)
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: scheme.outline,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.l10n.filesError('$error'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          _ => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        },
      );
    }

    return ListView(
      key: const ValueKey('files-columns'),
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < dirs.length; i++) column(i),
        if (selectedFile != null)
          SizedBox(
            width: 300,
            child: FilePreview(
              entry: selectedFile,
              sessionId: widget.sessionId,
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({
    required this.items,
    required this.selected,
    required this.sessionId,
    required this.actions,
  });

  final List<RemoteEntry> items;
  final String? selected;
  final String sessionId;
  final _ItemActions actions;

  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
  final _strip = ScrollController();

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = widget.items;
    final current = items.firstWhere(
      (e) => e.path == widget.selected,
      orElse: () => items.first,
    );
    return Column(
      key: const ValueKey('files-gallery'),
      children: [
        Expanded(
          child: FilePreview(
            key: ValueKey('preview-${current.path}'),
            entry: current,
            sessionId: widget.sessionId,
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        SizedBox(
          height: 92,
          child: ListView.builder(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              final sel = e.path == current.path;
              return widget.actions.wrap(
                e,
                Container(
                  width: 84,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: sel ? scheme.secondaryContainer : null,
                    borderRadius: BorderRadius.circular(10),
                    border: sel
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    children: [
                      FileIcon(e, size: 36),
                      const SizedBox(height: 4),
                      Text(
                        e.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
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
  }
}

// ---------------------------------------------------------------------------
// Preview

/// Shows an image or the start of a text file, otherwise a large icon
/// with details.
class FilePreview extends ConsumerWidget {
  const FilePreview({
    super.key,
    required this.entry,
    required this.sessionId,
    this.compact = false,
  });

  final RemoteEntry entry;
  final String sessionId;
  final bool compact;

  static const _maxImage = 8 * 1024 * 1024;
  static const _maxText = 64 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = kindOf(entry);
    final n = ref.read(fileBrowserProvider(sessionId).notifier);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.name,
          style: theme.textTheme.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        for (final (k, v) in [
          (l.colKind, kindLabel(l, entry)),
          if (!entry.isDir) (l.colSize, formatSize(entry.size)),
          (l.colModified, formatModified(entry.modified)),
          (l.filesPermissions, formatMode(entry.mode)),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$k  $v',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    Widget content;
    final size = entry.size ?? 0;
    if (kind == FileKind.image &&
        entry.extension != 'svg' &&
        size > 0 &&
        size <= _maxImage) {
      content = FutureBuilder<Uint8List>(
        future: n.preview(entry.path, maxBytes: size + 1),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(
            bytes,
            key: const ValueKey('preview-image'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Center(child: FileIcon(entry, size: 96)),
          );
        },
      );
    } else if ((kind == FileKind.text ||
            kind == FileKind.code ||
            (kind == FileKind.file && size <= _maxText * 4)) &&
        !entry.isDir) {
      content = FutureBuilder<Uint8List>(
        future: n.preview(entry.path, maxBytes: _maxText),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) {
            return snap.hasError
                ? Center(child: FileIcon(entry, size: 96))
                : const Center(child: CircularProgressIndicator());
          }
          if (bytes.contains(0)) {
            return Center(child: FileIcon(entry, size: 96)); // binary
          }
          final text = utf8.decode(bytes, allowMalformed: true);
          final terminal = terminalThemeFor(scheme);
          return Container(
            color: terminal.background,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text,
                key: const ValueKey('preview-text'),
                style: TextStyle(
                  fontFamily: monoFontFamily,
                  fontFamilyFallback: monoFontFallback,
                  fontSize: 12,
                  height: 1.4,
                  color: terminal.foreground,
                ),
              ),
            ),
          );
        },
      );
    } else {
      content = Center(child: FileIcon(entry, size: compact ? 72 : 112));
    }

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: content,
              ),
            ),
            const SizedBox(height: 10),
            // Short panels: the details scroll instead of overflowing.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(primary: false, child: details),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 220,
            child: SingleChildScrollView(primary: false, child: details),
          ),
        ],
      ),
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({
    required this.entry,
    required this.sessionId,
    required this.onDownload,
  });

  final RemoteEntry entry;
  final String sessionId;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (screen.width * 0.7).clamp(360, 1000),
        height: (screen.height * 0.7).clamp(300, 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilePreview(entry: entry, sessionId: sessionId),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onDownload();
                    },
                    icon: const Icon(Icons.download),
                    label: Text(l.filesDownload),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
