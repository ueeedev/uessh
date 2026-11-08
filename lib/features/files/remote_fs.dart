import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// One file or folder on the server.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isLink = false,
    this.size,
    this.modified,
    this.mode,
  });

  final String name;
  final String path;

  /// A folder (or a link to one).
  final bool isDir;
  final bool isLink;
  final int? size;
  final DateTime? modified;

  /// Unix permission bits.
  final int? mode;

  bool get isHidden => name.startsWith('.');

  /// Lower-case extension without the dot ('' if none).
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isExecutable => !isDir && mode != null && (mode! & 0x49) != 0;
}

/// Files on the server, as needed by the file browser. Replaceable in
/// tests.
abstract class RemoteFs {
  /// The login user's home folder.
  Future<String> home();

  /// Entries of folder [dir] (without "." and "..").
  Future<List<RemoteEntry>> list(String dir);

  /// The first [maxBytes] bytes of file [path].
  Future<Uint8List> read(String path, {int maxBytes = 1 << 20});

  /// Copies file [path] to local [target], reporting bytes done.
  Future<void> download(
    String path,
    File target, {
    void Function(int done)? onProgress,
  });

  /// Copies local [source] to [path] on the server (replacing it),
  /// reporting bytes sent.
  Future<void> upload(
    File source,
    String path, {
    void Function(int sent)? onProgress,
  });

  /// Creates folder [path]; fine if it already exists.
  Future<void> mkdir(String path);
}

/// [RemoteFs] over SFTP.
class SftpRemoteFs implements RemoteFs {
  SftpRemoteFs(this.client);

  final SftpClient client;

  @override
  Future<String> home() => client.absolute('.');

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    final names = await client.listdir(dir);
    final out = <RemoteEntry>[];
    final links = <int>[];
    for (final n in names) {
      if (n.filename == '.' || n.filename == '..') continue;
      final a = n.attr;
      if (a.isSymbolicLink) links.add(out.length);
      out.add(
        RemoteEntry(
          name: n.filename,
          path: joinPath(dir, n.filename),
          isDir: a.isDirectory,
          isLink: a.isSymbolicLink,
          size: a.size,
          modified: a.modifyTime == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(a.modifyTime! * 1000),
          mode: a.mode?.value,
        ),
      );
    }
    // Links: is the target a folder? (A few at a time.)
    for (var i = 0; i < links.length; i += 16) {
      await Future.wait([
        for (final k in links.skip(i).take(16))
          client
              .stat(out[k].path)
              .then((t) {
                final e = out[k];
                out[k] = RemoteEntry(
                  name: e.name,
                  path: e.path,
                  isDir: t.isDirectory,
                  isLink: true,
                  size: t.size,
                  modified: e.modified,
                  mode: e.mode,
                );
              })
              .catchError((_) {}), // broken link: stays a file
      ]);
    }
    return out;
  }

  @override
  Future<Uint8List> read(String path, {int maxBytes = 1 << 20}) async {
    final f = await client.open(path);
    try {
      return await f.readBytes(length: maxBytes);
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> upload(
    File source,
    String path, {
    void Function(int sent)? onProgress,
  }) async {
    final f = await client.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await f.write(
        source.openRead().map(Uint8List.fromList),
        onProgress: onProgress,
      );
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> mkdir(String path) async {
    try {
      await client.mkdir(path);
    } catch (_) {
      // Already there (as a folder) is fine; anything else shows up when
      // files are written into it.
      final a = await client.stat(path);
      if (!a.isDirectory) rethrow;
    }
  }

  @override
  Future<void> download(
    String path,
    File target, {
    void Function(int done)? onProgress,
  }) async {
    final f = await client.open(path);
    final sink = target.openWrite();
    var done = 0;
    try {
      await for (final chunk in f.read()) {
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done);
      }
    } finally {
      await sink.close();
      await f.close();
    }
  }
}

/// [dir] + [name] with one slash between.
String joinPath(String dir, String name) =>
    dir.endsWith('/') ? '$dir$name' : '$dir/$name';

/// The folder holding [path] ('/' for top-level entries and '/').
String parentPath(String path) {
  if (path == '/' || !path.contains('/')) return '/';
  final trimmed = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final i = trimmed.lastIndexOf('/');
  return i <= 0 ? '/' : trimmed.substring(0, i);
}

/// '/', '/var', '/var/log' for '/var/log'.
List<String> ancestorsOf(String path) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  return [
    '/',
    for (var i = 0; i < parts.length; i++) '/${parts.take(i + 1).join('/')}',
  ];
}

/// Quotes [s] for a POSIX shell.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
