import 'dart:convert';
import 'dart:io';

/// Small JSON file helper. Writes go to a temp file first, then rename,
/// so a crash mid-write never leaves a half-written file. Writes to the
/// same path run one after another, so quick successive saves can't
/// trip over each other's temp file.
class JsonFile {
  JsonFile(this.file);

  final File file;

  static final _queues = <String, Future<void>>{};

  Future<Object?> read() async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    if (text.trim().isEmpty) return null;
    return jsonDecode(text);
  }

  Future<void> write(Object? data) {
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final path = file.path;
    final previous = _queues[path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => _writeNow(text));
    _queues[path] = next;
    // Drop the queue entry once idle so the map doesn't grow.
    next.whenComplete(() {
      if (identical(_queues[path], next)) _queues.remove(path);
    }).ignore();
    return next;
  }

  Future<void> _writeNow(String text) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text);
    await tmp.rename(file.path);
  }
}
