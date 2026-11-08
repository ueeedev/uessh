import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/app_providers.dart';
import '../../core/json_file.dart';
import '../hosts/host.dart' show generateId;

/// Wire format a provider speaks.
enum AiProtocol {
  /// Anthropic Messages API (`/v1/messages`).
  anthropic,

  /// OpenAI Chat Completions (`/chat/completions`), which most providers
  /// also offer.
  openai,
}

/// The built-in providers, plus [custom] for any compatible endpoint.
enum AiVendor {
  anthropic(
    label: 'Anthropic Claude',
    baseUrl: 'https://api.anthropic.com',
    protocol: AiProtocol.anthropic,
    keyUrl: 'https://platform.claude.com/settings/keys',
    fallbackModels: [
      'claude-opus-5-5',
      'claude-sonnet-5-5',
      'claude-haiku-5-5',
      'claude-fable-5-1',
    ],
  ),
  openai(
    label: 'OpenAI ChatGPT',
    baseUrl: 'https://api.openai.com/v1',
    protocol: AiProtocol.openai,
    keyUrl: 'https://platform.openai.com/api-keys',
  ),
  deepseek(
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    protocol: AiProtocol.openai,
    keyUrl: 'https://platform.deepseek.com/api_keys',
    fallbackModels: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  gemini(
    label: 'Google Gemini',
    // Gemini's OpenAI-compatible endpoint.
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    protocol: AiProtocol.openai,
    keyUrl: 'https://aistudio.google.com/apikey',
  ),
  grok(
    label: 'xAI Grok',
    baseUrl: 'https://api.x.ai/v1',
    protocol: AiProtocol.openai,
    keyUrl: 'https://console.x.ai',
  ),
  custom(label: '', baseUrl: '', protocol: AiProtocol.openai, keyUrl: '');

  const AiVendor({
    required this.label,
    required this.baseUrl,
    required this.protocol,
    required this.keyUrl,
    this.fallbackModels = const [],
  });

  final String label;
  final String baseUrl;
  final AiProtocol protocol;

  /// Where to create an API key.
  final String keyUrl;

  /// Shown when the provider's model list can't be fetched.
  final List<String> fallbackModels;

  static const builtIn = [anthropic, openai, deepseek, gemini, grok];
}

/// One configured AI provider. Its API key is not stored here but in the
/// encrypted vault (see [AiConfigNotifier.apiKey]).
class AiProvider {
  const AiProvider({
    required this.id,
    required this.vendor,
    this.name = '',
    this.baseUrl = '',
    this.protocol,
    this.extraModels = const [],
  });

  /// Built-in providers use the vendor name as id; custom ones a random id.
  final String id;
  final AiVendor vendor;

  /// Custom providers only.
  final String name;

  /// Overrides the vendor's default base URL when not empty (proxies).
  final String baseUrl;

  /// Custom providers only; built-ins use the vendor's.
  final AiProtocol? protocol;

  /// Model ids typed by the user, for endpoints that don't list models.
  final List<String> extraModels;

  bool get isCustom => vendor == AiVendor.custom;

  String get displayName => isCustom ? name : vendor.label;

  AiProtocol get effectiveProtocol => protocol ?? vendor.protocol;

  /// Base URL without a trailing slash.
  String get effectiveBaseUrl {
    final url = baseUrl.trim().isNotEmpty ? baseUrl.trim() : vendor.baseUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static AiProvider builtIn(AiVendor v) => AiProvider(id: v.name, vendor: v);

  static AiProvider newCustom() =>
      AiProvider(id: 'custom-${generateId()}', vendor: AiVendor.custom);

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    AiProtocol? protocol,
    List<String>? extraModels,
  }) => AiProvider(
    id: id,
    vendor: vendor,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    protocol: protocol ?? this.protocol,
    extraModels: extraModels ?? this.extraModels,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'vendor': vendor.name,
    if (name.isNotEmpty) 'name': name,
    if (baseUrl.isNotEmpty) 'baseUrl': baseUrl,
    if (protocol != null) 'protocol': protocol!.name,
    if (extraModels.isNotEmpty) 'extraModels': extraModels,
  };

  static AiProvider? fromJson(Object? json) {
    if (json is! Map) return null;
    final vendor = AiVendor.values.asNameMap()[json['vendor']];
    final id = json['id'];
    if (vendor == null || id is! String) return null;
    return AiProvider(
      id: id,
      vendor: vendor,
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      protocol: AiProtocol.values.asNameMap()[json['protocol']],
      extraModels: [
        for (final m in (json['extraModels'] as List? ?? const []))
          if (m is String && m.trim().isNotEmpty) m.trim(),
      ],
    );
  }
}

/// Whether the assistant may run commands on the server.
enum AiToolMode {
  /// No tools: the assistant only answers.
  off,

  /// Every command waits for the user's approval.
  askAll,

  /// Read-only commands run right away; anything else waits for approval.
  autoReadOnly,

  /// Every command runs without asking. Dangerous: the model can change
  /// or delete anything the SSH user can.
  allowAll,
}

/// A model to chat with: which provider, which model id.
typedef AiModelRef = ({String providerId, String model});

/// Everything in ai.json.
class AiConfig {
  const AiConfig({
    this.providers = const [],
    this.configured = const {},
    this.selected,
    this.toolMode = AiToolMode.autoReadOnly,
  });

  /// Built-ins (always listed, edited or not) followed by custom ones.
  final List<AiProvider> providers;

  /// Ids of providers that have an API key.
  final Set<String> configured;

  /// Model picked last in the AI panel.
  final AiModelRef? selected;

  /// Whether the assistant may run commands, and which need approval.
  final AiToolMode toolMode;

  AiProvider? byId(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<AiProvider> get ready => [
    for (final p in providers)
      if (configured.contains(p.id)) p,
  ];

  AiConfig copyWith({
    List<AiProvider>? providers,
    Set<String>? configured,
    AiModelRef? selected,
    AiToolMode? toolMode,
  }) => AiConfig(
    providers: providers ?? this.providers,
    configured: configured ?? this.configured,
    selected: selected ?? this.selected,
    toolMode: toolMode ?? this.toolMode,
  );
}

/// Loads and saves AI providers. API keys go to the vault under
/// `uessh.ai.<id>.key`, never to ai.json.
class AiConfigNotifier extends AsyncNotifier<AiConfig> {
  JsonFile get _file =>
      JsonFile(File('${ref.read(dataDirProvider).path}/ai.json'));

  static String keyName(String providerId) => 'uessh.ai.$providerId.key';

  @override
  Future<AiConfig> build() async {
    final saved = <String, AiProvider>{};
    AiModelRef? selected;
    var toolMode = AiToolMode.autoReadOnly;
    try {
      final data = await _file.read();
      if (data is Map) {
        for (final p in (data['providers'] as List? ?? const [])) {
          final provider = AiProvider.fromJson(p);
          if (provider != null) saved[provider.id] = provider;
        }
        toolMode = AiToolMode.values.asNameMap()[data['toolMode']] ?? toolMode;
        final sel = data['selected'];
        if (sel is Map &&
            sel['providerId'] is String &&
            sel['model'] is String) {
          selected = (
            providerId: sel['providerId'] as String,
            model: sel['model'] as String,
          );
        }
      }
    } catch (e) {
      log.warn('ai', 'Could not read ai.json: $e');
    }
    final providers = [
      for (final v in AiVendor.builtIn) saved[v.name] ?? AiProvider.builtIn(v),
      for (final p in saved.values)
        if (p.isCustom) p,
    ];
    return AiConfig(
      providers: providers,
      configured: _configured(providers),
      selected: selected,
      toolMode: toolMode,
    );
  }

  Set<String> _configured(List<AiProvider> providers) {
    final vault = ref.read(vaultProvider);
    return {
      for (final p in providers)
        if ((_tryRead(vault.read, keyName(p.id)) ?? '').isNotEmpty) p.id,
    };
  }

  static String? _tryRead(String? Function(String) read, String key) {
    try {
      return read(key);
    } catch (_) {
      return null; // vault locked
    }
  }

  /// The provider's API key, or null if none (or the vault is locked).
  String? apiKey(String providerId) =>
      _tryRead(ref.read(vaultProvider).read, keyName(providerId));

  AiConfig get _current => state.value ?? const AiConfig();

  /// Saves [provider]; [apiKey] null keeps the current key, '' removes it.
  Future<void> saveProvider(AiProvider provider, {String? apiKey}) async {
    if (apiKey != null) {
      await ref
          .read(vaultProvider)
          .write(keyName(provider.id), apiKey.trim().isEmpty ? null : apiKey);
    }
    final providers = [..._current.providers];
    final i = providers.indexWhere((p) => p.id == provider.id);
    if (i >= 0) {
      providers[i] = provider;
    } else {
      providers.add(provider);
    }
    await _commit(_current.copyWith(providers: providers));
  }

  /// Removes a custom provider, or clears a built-in one (key and edits).
  Future<void> removeProvider(String id) async {
    await ref.read(vaultProvider).write(keyName(id), null);
    final providers = [
      for (final p in _current.providers)
        if (p.id != id) p else if (!p.isCustom) AiProvider.builtIn(p.vendor),
    ];
    await _commit(_current.copyWith(providers: providers));
  }

  Future<void> select(AiModelRef model) =>
      _commit(_current.copyWith(selected: model));

  Future<void> setToolMode(AiToolMode mode) =>
      _commit(_current.copyWith(toolMode: mode));

  Future<void> _commit(AiConfig next) async {
    final config = next.copyWith(configured: _configured(next.providers));
    state = AsyncData(config);
    final sel = config.selected;
    await _file.write({
      'providers': [
        for (final p in config.providers)
          // Untouched built-ins need no entry.
          if (p.isCustom || p.baseUrl.isNotEmpty || p.extraModels.isNotEmpty)
            p.toJson(),
      ],
      if (sel != null)
        'selected': {'providerId': sel.providerId, 'model': sel.model},
      'toolMode': config.toolMode.name,
    });
  }
}

final aiConfigProvider = AsyncNotifierProvider<AiConfigNotifier, AiConfig>(
  AiConfigNotifier.new,
);
