import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'remote_fs.dart';

/// This computer's files, for the file browser of a local terminal.
///
/// Paths use '/' everywhere, like on a server. On Windows a drive is the
/// first folder ('/C:/Users/me'), and '/' lists the drives, so the
/// browser's path handling (parent, breadcrumbs) works unchanged.
class LocalFs implements RemoteFs {
  LocalFs({bool? windows}) : windows = windows ?? Platform.isWindows;

  final bool windows;

  /// The browser's form of native [path] ('C:\Users' -> '/C:/Users').
  String fromNative(String path) {
    if (!windows) return path;
    var p = path.replaceAll(r'\', '/');
    if (p.length >= 2 && p[1] == ':') p = '/$p';
    if (p.length > 4 && p.endsWith('/')) p = p.substring(0, p.length - 1);
    return p;
  }

  /// The native path for browser path [path] ('/C:/Users' -> 'C:/Users').
  String toNative(String path) {
    if (!windows) return path;
    var p = path.startsWith('/') ? path.substring(1) : path;
    // 'C:' alone means "the current folder on C:"; the drive's root is 'C:/'.
    if (p.length == 2 && p[1] == ':') p = '$p/';
    return p;
  }

  @override
  Future<String> home() async {
    final env = Platform.environment;
    final home = windows ? env['USERPROFILE'] : env['HOME'];
    return fromNative(home ?? (windows ? r'C:\' : '/'));
  }

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    if (windows && (dir == '/' || dir.isEmpty)) return _drives();
    final out = <RemoteEntry>[];
    await for (final e in Directory(toNative(dir)).list(followLinks: false)) {
      final name = e.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => e.path,
      );
      final path = joinPath(dir, name);
      try {
        final isLink = e is Link;
        // For links: what they point to (a folder link opens as a folder).
        final stat = await FileStat.stat(e.path);
        final isDir = stat.type == FileSystemEntityType.directory;
        out.add(
          RemoteEntry(
            name: name,
            path: path,
            isDir: isDir,
            isLink: isLink,
            size: isDir ? null : stat.size,
            modified: stat.modified,
            mode: windows ? null : stat.mode,
          ),
        );
      } catch (_) {
        // Unreadable entries (permissions, broken links): name only.
        out.add(RemoteEntry(name: name, path: path, isDir: false));
      }
    }
    return out;
  }

  Future<List<RemoteEntry>> _drives() async => [
    for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''))
      if (await Directory('$letter:/').exists())
        RemoteEntry(name: '$letter:', path: '/$letter:', isDir: true),
  ];

  @override
  Future<Uint8List> read(String path, {int maxBytes = 1 << 20}) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in File(toNative(path)).openRead(0, maxBytes)) {
      out.add(chunk);
    }
    return out.takeBytes();
  }

  @override
  Future<void> download(
    String path,
    File target, {
    void Function(int done)? onProgress,
  }) => _copy(File(toNative(path)), target, onProgress);

  @override
  Future<void> upload(
    File source,
    String path, {
    void Function(int sent)? onProgress,
  }) => _copy(source, File(toNative(path)), onProgress);

  @override
  Future<void> mkdir(String path) async {
    await Directory(toNative(path)).create();
  }

  static Future<void> _copy(
    File from,
    File to,
    void Function(int)? onProgress,
  ) async {
    final sink = to.openWrite();
    var done = 0;
    try {
      await for (final chunk in from.openRead()) {
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done);
      }
    } finally {
      await sink.close();
    }
  }
}
