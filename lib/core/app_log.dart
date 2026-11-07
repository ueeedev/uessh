import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = time;
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final lvl = switch (level) {
      LogLevel.info => 'INFO ',
      LogLevel.warning => 'WARN ',
      LogLevel.error => 'ERROR',
    };
    return '$stamp $lvl [$tag] $message';
  }
}

/// The app's log: kept in memory for the log viewer and, once
/// [attachFile] is called, appended to `logs/uessh.log` in the app data
/// directory (rotated at 1 MB, one old file kept).
///
/// Never log passwords, keys or passphrases.
class AppLog extends ChangeNotifier {
  AppLog._();

  static final instance = AppLog._();

  static const maxEntries = 2000;
  static const maxFileBytes = 1024 * 1024;

  final _entries = ListQueue<LogEntry>();
  File? _file;
  IOSink? _sink;
  int _fileBytes = 0;

  UnmodifiableListView<LogEntry> get entries => UnmodifiableListView(_entries);

  String? get filePath => _file?.path;

  void info(String tag, String message) => _add(LogLevel.info, tag, message);

  void warn(String tag, String message) => _add(LogLevel.warning, tag, message);

  void error(String tag, String message, [Object? error, StackTrace? stack]) {
    final detail = StringBuffer(message);
    if (error != null) detail.write(': $error');
    if (stack != null) detail.write('\n$stack');
    _add(LogLevel.error, tag, detail.toString());
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// All entries as text, oldest first (for "copy").
  String export() => _entries.map((e) => e.format()).join('\n');

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    _writeToFile(entry);
    notifyListeners();
  }

  Future<void> attachFile(Directory dataDir) async {
    final dir = Directory('${dataDir.path}/logs');
    await dir.create(recursive: true);
    final file = File('${dir.path}/uessh.log');
    _fileBytes = await file.exists() ? await file.length() : 0;
    _file = file;
    _sink = file.openWrite(mode: FileMode.append);
    // Write what was logged before the file was ready.
    for (final e in _entries) {
      _writeToFile(e);
    }
  }

  void _writeToFile(LogEntry entry) {
    final sink = _sink;
    if (sink == null) return;
    final line = '${entry.format()}\n';
    sink.write(line);
    _fileBytes += line.length;
    if (_fileBytes > maxFileBytes) unawaited(_rotate());
  }

  Future<void> _rotate() async {
    final file = _file, sink = _sink;
    if (file == null || sink == null) return;
    _sink = null; // stop writing while rotating
    try {
      await sink.flush();
      await sink.close();
      final old = File('${file.path}.1');
      if (await old.exists()) await old.delete();
      await file.rename(old.path);
    } catch (_) {
      // Keep logging to memory even if rotation fails.
    }
    _fileBytes = 0;
    _sink = file.openWrite(mode: FileMode.append);
  }

  /// Routes debugPrint and uncaught Flutter / platform errors into the
  /// log. Call once at startup.
  void captureErrors() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) info('debug', message);
      original(message, wrapWidth: wrapWidth);
    };
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      error('flutter', details.exceptionAsString(), null, details.stack);
      previousFlutter?.call(details);
    };
    PlatformDispatcher.instance.onError = (e, stack) {
      error('uncaught', 'Unhandled error', e, stack);
      return false; // let the default handler report it too
    };
  }
}

/// Shorthand: `log.info('ssh', '...')`.
AppLog get log => AppLog.instance;
