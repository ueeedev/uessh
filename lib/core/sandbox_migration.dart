import 'dart:io';

/// Files that mean the app already has data in a folder.
const _dataFiles = ['hosts.json', 'settings.json', 'vault.json', 'vault.key'];

/// Up to 0.1.4 the macOS app ran in the App Sandbox, which keeps its data
/// in a container (`~/Library/Containers/<bundle id>/...`). Without the
/// sandbox the same app reads `~/Library/Application Support/<bundle id>`.
///
/// Copies the container's data to [dataDir] once, when [dataDir] has no
/// data of its own yet. The container is left as it was (a backup).
/// Returns whether anything was copied.
Future<bool> migrateSandboxData(
  Directory dataDir, {
  required String home,
}) async {
  if (await _hasData(dataDir)) return false;
  final bundleId = dataDir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
  final container = Directory(
    '$home/Library/Containers/$bundleId/Data/Library/Application Support/$bundleId',
  );
  if (!await _hasData(container)) return false;
  await _copyDir(container, dataDir);
  return true;
}

Future<bool> _hasData(Directory dir) async {
  for (final name in _dataFiles) {
    if (await File('${dir.path}/$name').exists()) return true;
  }
  return false;
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final e in from.list(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final target = '${to.path}/$name';
    if (e is Directory) {
      await _copyDir(e, Directory(target));
    } else if (e is File) {
      // Keep existing files (e.g. today's log, written before this runs).
      if (!await File(target).exists()) await e.copy(target);
    }
  }
}
