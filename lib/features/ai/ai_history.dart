import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/app_providers.dart';
import '../../core/json_file.dart';
import 'ai_chat.dart';
import 'ai_client.dart';

/// A saved AI conversation, as listed (without its messages).
class AiConversationInfo {
  const AiConversationInfo({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.title,
    required this.updatedAt,
    this.model,
    this.messageCount = 0,
  });

  final String id;
  final String hostId;
  final String hostName;

  /// The first question, shortened.
  final String title;
  final DateTime updatedAt;
  final String? model;
  final int messageCount;

  Map<String, Object?> toJson() => {
    'id': id,
    'hostId': hostId,
    'hostName': hostName,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    if (model != null) 'model': model,
    'count': messageCount,
  };

  static AiConversationInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse(j['updatedAt'] as String? ?? '');
    if (j['id'] is! String || at == null) return null;
    return AiConversationInfo(
      id: j['id'] as String,
      hostId: j['hostId'] as String? ?? '',
      hostName: j['hostName'] as String? ?? '',
      title: j['title'] as String? ?? '',
      updatedAt: at,
      model: j['model'] as String?,
      messageCount: (j['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A whole conversation: what is shown, and the turns sent to the model
/// (so it can be continued).
class AiConversation {
  const AiConversation({
    required this.info,
    required this.messages,
    required this.turns,
  });

  final AiConversationInfo info;
  final List<AiMessage> messages;
  final List<AiTurn> turns;

  Map<String, Object?> toJson() => {
    'info': info.toJson(),
    'messages': [for (final m in messages) m.toJson()],
    'turns': [for (final t in turns) t.toJson()],
  };

  static AiConversation? fromJson(Object? j) {
    if (j is! Map) return null;
    final info = AiConversationInfo.fromJson(j['info']);
    if (info == null) return null;
    List<Map<String, Object?>> maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        if (e is Map) e.cast<String, Object?>(),
    ];
    return AiConversation(
      info: info,
      messages: [for (final m in maps(j['messages'])) AiMessage.fromJson(m)],
      turns: [for (final t in maps(j['turns'])) AiTurn.fromJson(t)],
    );
  }
}

/// Keeps AI conversations on disk, encrypted with the vault's key (they
/// can hold command output and configuration): one file per
/// conversation plus an index, under `ai_history/`. Newest first; at most
/// [maxConversations] are kept.
class AiHistoryNotifier extends AsyncNotifier<List<AiConversationInfo>> {
  static const maxConversations = 200;

  Directory get _dir =>
      Directory('${ref.read(dataDirProvider).path}/ai_history');
  JsonFile get _indexFile => JsonFile(File('${_dir.path}/index.json'));
  JsonFile _file(String id) => JsonFile(File('${_dir.path}/$id.json'));

  @override
  Future<List<AiConversationInfo>> build() async {
    try {
      final data = await _readSealed(_indexFile);
      final list = [
        for (final e in (data as List? ?? const []))
          ?AiConversationInfo.fromJson(e),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (e) {
      log.warn('ai', 'Could not read AI history: $e');
      return const [];
    }
  }

  Future<Object?> _readSealed(JsonFile file) async {
    final raw = await file.read();
    if (raw is! Map) return null;
    final plain = await ref.read(vaultProvider).unseal(raw.cast());
    return jsonDecode(utf8.decode(plain));
  }

  Future<void> _writeSealed(JsonFile file, Object? data) async {
    final sealed = await ref
        .read(vaultProvider)
        .seal(utf8.encode(jsonEncode(data)));
    await file.write(sealed);
  }

  /// Saves (or updates) [conversation].
  Future<void> save(AiConversation conversation) async {
    try {
      final current = await future;
      await _writeSealed(_file(conversation.info.id), conversation.toJson());
      final list = [
        conversation.info,
        for (final c in current)
          if (c.id != conversation.info.id) c,
      ];
      final keep = list.take(maxConversations).toList();
      for (final old in list.skip(maxConversations)) {
        await _delete(old.id);
      }
      state = AsyncData(keep);
      await _writeSealed(_indexFile, [for (final c in keep) c.toJson()]);
    } catch (e) {
      log.warn('ai', 'Could not save AI conversation: $e');
    }
  }

  /// The whole conversation [id], or null if it can't be read.
  Future<AiConversation?> load(String id) async {
    try {
      return AiConversation.fromJson(await _readSealed(_file(id)));
    } catch (e) {
      log.warn('ai', 'Could not read AI conversation $id: $e');
      return null;
    }
  }

  Future<void> delete(String id) async {
    final current = await future;
    await _delete(id);
    final list = [
      for (final c in current)
        if (c.id != id) c,
    ];
    state = AsyncData(list);
    await _writeSealed(_indexFile, [for (final c in list) c.toJson()]);
  }

  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
    state = const AsyncData([]);
  }

  Future<void> _delete(String id) async {
    final f = File('${_dir.path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}

final aiHistoryProvider =
    AsyncNotifierProvider<AiHistoryNotifier, List<AiConversationInfo>>(
      AiHistoryNotifier.new,
    );
