import 'dart:io';

import '../../core/json_file.dart';
import '../hosts/host.dart' show generateId;

/// Script / command language of a saved snippet.
enum SnippetLanguage {
  shell,
  bash,
  python,
  powershell,
  node,
  other;

  /// Canonical file extension (without leading dot) for import/export hints.
  String get extension => switch (this) {
    shell => 'sh',
    bash => 'sh',
    python => 'py',
    powershell => 'ps1',
    node => 'js',
    other => 'txt',
  };

  /// Best-effort language guess from a script file name.
  static SnippetLanguage fromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.py')) return python;
    if (lower.endsWith('.bash')) return bash;
    if (lower.endsWith('.sh') || lower.endsWith('.zsh')) return shell;
    if (lower.endsWith('.ps1')) return powershell;
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return node;
    return other;
  }
}

/// A reusable command or script saved by the user.
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.content,
    this.language = SnippetLanguage.shell,
    this.description,
    this.group,
    this.updatedAt,
  });

  final String id;
  final String name;
  final SnippetLanguage language;
  final String content;
  final String? description;
  final String? group;
  final DateTime? updatedAt;

  static String newId() => generateId();

  /// Unique placeholder names found as `{{name}}` in [content], in order of
  /// first appearance.
  List<String> get placeholders => extractPlaceholders(content);

  Snippet copyWith({
    String? name,
    SnippetLanguage? language,
    String? content,
    Object? description = _keep,
    Object? group = _keep,
    DateTime? updatedAt,
  }) => Snippet(
    id: id,
    name: name ?? this.name,
    language: language ?? this.language,
    content: content ?? this.content,
    description: identical(description, _keep)
        ? this.description
        : description as String?,
    group: identical(group, _keep) ? this.group : group as String?,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'language': language.name,
    'content': content,
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (group != null && group!.isNotEmpty) 'group': group,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  factory Snippet.fromJson(Map<String, Object?> json) => Snippet(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? '',
    language:
        SnippetLanguage.values.asNameMap()[json['language']] ??
        SnippetLanguage.shell,
    content: json['content'] as String? ?? '',
    description: json['description'] as String?,
    group: json['group'] as String?,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

final _placeholderPattern = RegExp(
  r'\{\{\s*([a-zA-Z0-9_.\-\u4e00-\u9fff]+)\s*\}\}',
);

/// Extracts unique `{{name}}` placeholder names in order of first appearance.
List<String> extractPlaceholders(String content) {
  final seen = <String>{};
  final result = <String>[];
  for (final m in _placeholderPattern.allMatches(content)) {
    final name = m.group(1)!;
    if (seen.add(name)) result.add(name);
  }
  return result;
}

/// Replaces `{{name}}` placeholders in [content] using [values].
String renderSnippetTemplate(String content, Map<String, String> values) =>
    content.replaceAllMapped(_placeholderPattern, (m) {
      final name = m.group(1)!;
      return values[name] ?? m.group(0)!;
    });

/// Reads and writes `snippets.json` in the app data directory.
class SnippetRepository {
  SnippetRepository({required Directory dataDir})
    : _file = JsonFile(File('${dataDir.path}/snippets.json'));

  final JsonFile _file;

  Future<List<Snippet>> load() async {
    try {
      final data = await _file.read();
      if (data is Map && data['snippets'] is List) {
        return [
          for (final item in data['snippets'] as List)
            if (item is Map) Snippet.fromJson(item.cast<String, Object?>()),
        ];
      }
    } on FormatException {
      // Corrupt file: start empty rather than failing to render the page.
    }
    return const [];
  }

  Future<void> save(List<Snippet> snippets) => _file.write({
    'version': 1,
    'snippets': [for (final s in snippets) s.toJson()],
  });
}
