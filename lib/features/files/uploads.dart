import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../l10n/l10n.dart';
import '../terminal/terminal_session.dart';
import 'file_browser.dart';
import 'remote_fs.dart';
import '../../widgets/toasts.dart';

/// A local file or folder to upload. [bookmark]: macOS sandbox access for
/// files dropped from outside the app.
class UploadSource {
  const UploadSource(this.path, {this.bookmark});

  final String path;
  final Uint8List? bookmark;

  String get name => path.split(Platform.pathSeparator).last;
}

enum UploadState { running, done, failed }

/// One upload (a drop or a pick, possibly many files).
class UploadJob {
  const UploadJob({
    required this.id,
    required this.sessionId,
    required this.targetDir,
    required this.totalBytes,
    required this.totalFiles,
    this.sentBytes = 0,
    this.doneFiles = 0,
    this.current = '',
    this.state = UploadState.running,
    this.error,
  });

  final int id;
  final String sessionId;
  final String targetDir;
  final int totalBytes;
  final int totalFiles;
  final int sentBytes;
  final int doneFiles;

  /// Name of the file being sent.
  final String current;
  final UploadState state;
  final String? error;

  double get progress => totalBytes == 0
      ? (state == UploadState.done ? 1 : 0)
      : sentBytes / totalBytes;

  UploadJob copyWith({
    int? sentBytes,
    int? doneFiles,
    String? current,
    UploadState? state,
    String? error,
  }) => UploadJob(
    id: id,
    sessionId: sessionId,
    targetDir: targetDir,
    totalBytes: totalBytes,
    totalFiles: totalFiles,
    sentBytes: sentBytes ?? this.sentBytes,
    doneFiles: doneFiles ?? this.doneFiles,
    current: current ?? this.current,
    state: state ?? this.state,
    error: error ?? this.error,
  );
}

/// Running and recent uploads. Finished ones disappear after a moment.
class UploadsNotifier extends Notifier<List<UploadJob>> {
  int _nextId = 1;

  @override
  List<UploadJob> build() => const [];

  /// Uploads [sources] into [targetDir] on [session]'s server, folders
  /// with their contents. Names in [skip] are left out.
  Future<UploadJob> upload({
    required TerminalSession session,
    required String targetDir,
    required List<UploadSource> sources,
    Set<String> skip = const {},
  }) async {
    final access = <Uint8List>[];
    for (final s in sources) {
      final b = s.bookmark;
      if (b != null && b.isNotEmpty) {
        try {
          if (await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: b,
          )) {
            access.add(b);
          }
        } catch (_) {}
      }
    }

    // What to send: folders to create, files with their remote paths.
    final dirs = <String>[];
    final files = <(File, String, int)>[];
    for (final s in sources) {
      if (skip.contains(s.name)) continue;
      final remote = joinPath(targetDir, s.name);
      final type = FileSystemEntity.typeSync(s.path);
      if (type == FileSystemEntityType.directory) {
        dirs.add(remote);
        final root = Directory(s.path);
        for (final e in root.listSync(recursive: true, followLinks: false)) {
          final rel = e.path
              .substring(root.path.length)
              .split(Platform.pathSeparator)
              .where((p) => p.isNotEmpty)
              .join('/');
          final target = '$remote/$rel';
          if (e is Directory) {
            dirs.add(target);
          } else if (e is File) {
            files.add((e, target, e.lengthSync()));
          }
        }
      } else if (type == FileSystemEntityType.file) {
        final f = File(s.path);
        files.add((f, remote, f.lengthSync()));
      }
    }

    var job = UploadJob(
      id: _nextId++,
      sessionId: session.id,
      targetDir: targetDir,
      totalBytes: files.fold(0, (a, f) => a + f.$3),
      totalFiles: files.length,
    );
    state = [...state, job];
    void update(UploadJob j) {
      job = j;
      if (!ref.mounted) return;
      state = [for (final x in state) x.id == j.id ? j : x];
    }

    try {
      final fs = await session.remoteFs();
      for (final d in dirs) {
        await fs.mkdir(d);
      }
      var sentBefore = 0;
      for (final (file, remote, size) in files) {
        update(job.copyWith(current: remote.split('/').last));
        await fs.upload(
          file,
          remote,
          onProgress: (sent) =>
              update(job.copyWith(sentBytes: sentBefore + sent)),
        );
        sentBefore += size;
        update(
          job.copyWith(sentBytes: sentBefore, doneFiles: job.doneFiles + 1),
        );
      }
      update(job.copyWith(state: UploadState.done));
      log.info('files', 'Uploaded ${files.length} file(s) to $targetDir');
    } catch (e) {
      log.warn('files', 'Upload to $targetDir failed: $e');
      update(job.copyWith(state: UploadState.failed, error: '$e'));
    } finally {
      for (final b in access) {
        unawaited(
          DesktopDrop.instance
              .stopAccessingSecurityScopedResource(bookmark: b)
              .catchError((Object _) => false),
        );
      }
    }

    // Show the new files where the browser is looking.
    if (ref.mounted && ref.read(fileBrowserProvider(session.id).exists)) {
      unawaited(
        ref
            .read(fileBrowserProvider(session.id).notifier)
            .load(targetDir, force: true, quiet: true),
      );
    }
    final finished = job;
    Timer(
      Duration(seconds: finished.state == UploadState.failed ? 10 : 4),
      () => dismiss(finished.id),
    );
    return finished;
  }

  void dismiss(int id) {
    if (!ref.mounted) return;
    state = [
      for (final j in state)
        if (j.id != id || j.state == UploadState.running) j,
    ];
  }
}

final uploadsProvider = NotifierProvider<UploadsNotifier, List<UploadJob>>(
  UploadsNotifier.new,
);

/// Uploads [sources] to [targetDir], asking first about names that
/// already exist there.
Future<void> uploadTo(
  BuildContext context,
  WidgetRef ref,
  TerminalSession session,
  String targetDir,
  List<UploadSource> sources,
) async {
  if (sources.isEmpty) return;
  final l = context.l10n;
  if (session.status != SessionStatus.connected) {
    showToast(l.uploadNotConnected, kind: ToastKind.error);
    return;
  }
  var skip = <String>{};
  try {
    final existing = {
      for (final e in await (await session.remoteFs()).list(targetDir)) e.name,
    };
    final clash = [
      for (final s in sources)
        if (existing.contains(s.name)) s.name,
    ];
    if (clash.isNotEmpty && context.mounted) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.file_copy_outlined),
          title: Text(l.overwriteTitle),
          content: Text(l.overwriteBody(targetDir, clash.join('、'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            TextButton(
              key: const ValueKey('overwrite-skip'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.overwriteSkip),
            ),
            FilledButton(
              key: const ValueKey('overwrite-replace'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.overwriteReplace),
            ),
          ],
        ),
      );
      if (replace == null) return;
      if (!replace) skip = clash.toSet();
    }
  } catch (_) {
    // Can't list the folder: the upload itself will tell.
  }
  final job = await ref
      .read(uploadsProvider.notifier)
      .upload(
        session: session,
        targetDir: targetDir,
        sources: sources,
        skip: skip,
      );
  if (job.state == UploadState.done && job.totalFiles > 0) {
    showToast(l.uploadDone(job.totalFiles, targetDir), kind: ToastKind.success);
  }
}

/// Asks for files (any number) and uploads them to [targetDir].
Future<void> pickAndUpload(
  BuildContext context,
  WidgetRef ref,
  TerminalSession session,
  String targetDir,
) async {
  final picked = await openFiles();
  if (picked.isEmpty || !context.mounted) return;
  await uploadTo(context, ref, session, targetDir, [
    for (final f in picked) UploadSource(f.path),
  ]);
}

/// Dropped items as upload sources.
List<UploadSource> dropSources(List<DropItem> items) => [
  for (final i in items) UploadSource(i.path, bookmark: i.extraAppleBookmark),
];

/// Progress of running uploads, as a small card (and failures, briefly).
class UploadProgressCard extends ConsumerWidget {
  const UploadProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(uploadsProvider);
    if (jobs.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('upload-progress'),
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final j in jobs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        switch (j.state) {
                          UploadState.running => Icons.upload,
                          UploadState.done => Icons.check_circle,
                          UploadState.failed => Icons.error_outline,
                        },
                        size: 18,
                        color: j.state == UploadState.failed
                            ? scheme.error
                            : scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              j.state == UploadState.failed
                                  ? l.uploadFailed(j.error ?? '')
                                  : l.uploadProgress(j.targetDir),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                            const SizedBox(height: 4),
                            if (j.state != UploadState.failed)
                              LinearProgressIndicator(
                                value: j.progress,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                l.uploadCount(j.doneFiles, j.totalFiles),
                                '${(j.progress * 100).round()}%',
                                if (j.state == UploadState.running &&
                                    j.current.isNotEmpty)
                                  j.current,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (j.state != UploadState.running)
                        IconButton(
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              ref.read(uploadsProvider.notifier).dismiss(j.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Covers a drop target while files are dragged over it: where they go.
class DropOverlay extends StatelessWidget {
  const DropOverlay({super.key, required this.label, this.radius = 16});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return IgnorePointer(
      child: Container(
        key: const ValueKey('drop-overlay'),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.14),
          border: Border.all(color: scheme.primary, width: 2),
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload, size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
