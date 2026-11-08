import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_config.dart';

/// A tool the model may call.
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.schema,
  });

  final String name;
  final String description;

  /// JSON Schema of the input object.
  final Map<String, Object?> schema;
}

/// A tool call the model made.
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.input,
    this.rawInput = '',
  });

  final String id;
  final String name;

  /// Parsed input, or null if the model sent invalid JSON ([rawInput]).
  final Map<String, Object?>? input;
  final String rawInput;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'input': input,
    if (rawInput.isNotEmpty) 'raw': rawInput,
  };

  factory AiToolCall.fromJson(Map<String, Object?> j) => AiToolCall(
    id: j['id'] as String,
    name: j['name'] as String,
    input: (j['input'] as Map?)?.cast<String, Object?>(),
    rawInput: j['raw'] as String? ?? '',
  );
}

/// What running a tool call returned.
class AiToolResult {
  const AiToolResult({
    required this.callId,
    required this.content,
    this.isError = false,
  });

  final String callId;
  final String content;
  final bool isError;

  Map<String, Object?> toJson() => {
    'id': callId,
    'content': content,
    if (isError) 'error': true,
  };

  factory AiToolResult.fromJson(Map<String, Object?> j) => AiToolResult(
    callId: j['id'] as String,
    content: j['content'] as String,
    isError: j['error'] == true,
  );
}

/// One turn of the conversation, in a provider-neutral form.
class AiTurn {
  const AiTurn.user(this.text, {this.toolResults = const []})
    : fromUser = true,
      toolCalls = const [],
      anthropicBlocks = null;

  const AiTurn.assistant(
    this.text, {
    this.toolCalls = const [],
    this.anthropicBlocks,
  }) : fromUser = false,
       toolResults = const [];

  final bool fromUser;
  final String text;

  /// Assistant turns: tools the model asked to run.
  final List<AiToolCall> toolCalls;

  /// User turns: results of the previous turn's [toolCalls].
  final List<AiToolResult> toolResults;

  /// Assistant turns from Claude: the content blocks exactly as received
  /// (thinking blocks and their signatures included), sent back unchanged.
  final List<Map<String, Object?>>? anthropicBlocks;

  bool get isEmpty =>
      text.trim().isEmpty && toolCalls.isEmpty && toolResults.isEmpty;

  Map<String, Object?> toJson() => {
    'user': fromUser,
    'text': text,
    if (toolCalls.isNotEmpty) 'calls': [for (final c in toolCalls) c.toJson()],
    if (toolResults.isNotEmpty)
      'results': [for (final r in toolResults) r.toJson()],
    if (anthropicBlocks != null) 'blocks': anthropicBlocks,
  };

  factory AiTurn.fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        (e as Map).cast<String, Object?>(),
    ];
    if (j['user'] == true) {
      return AiTurn.user(
        j['text'] as String? ?? '',
        toolResults: [
          for (final r in maps(j['results'])) AiToolResult.fromJson(r),
        ],
      );
    }
    return AiTurn.assistant(
      j['text'] as String? ?? '',
      toolCalls: [for (final c in maps(j['calls'])) AiToolCall.fromJson(c)],
      anthropicBlocks: j['blocks'] == null ? null : maps(j['blocks']),
    );
  }
}

/// A piece of a streamed reply.
sealed class AiDelta {
  const AiDelta();
}

/// Answer text.
class AiText extends AiDelta {
  const AiText(this.text);
  final String text;
}

/// Reasoning some models stream before answering (e.g. DeepSeek R1).
class AiReasoning extends AiDelta {
  const AiReasoning(this.text);
  final String text;
}

/// The model declined to answer (Anthropic `stop_reason: refusal`).
class AiRefusal extends AiDelta {
  const AiRefusal();
}

/// The reply was cut off by the output limit.
class AiTruncated extends AiDelta {
  const AiTruncated();
}

/// The reply is complete: the assistant turn to add to the history, with
/// any tool calls to run. Tool calls of a refused or cut-off reply are
/// left out (they may be incomplete).
class AiDone extends AiDelta {
  const AiDone(this.turn);
  final AiTurn turn;
}

class AiException implements Exception {
  const AiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : 'HTTP $status: $message';
}

/// Talks to AI providers. Replaceable in tests.
abstract class AiClient {
  /// Streams the reply to [turns], ending with [AiDone]. Cancelling the
  /// subscription stops the request.
  Stream<AiDelta> chat({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String system,
    required List<AiTurn> turns,
    List<AiTool> tools = const [],
  });

  /// Model ids the provider offers.
  Future<List<String>> listModels(AiProvider provider, String apiKey);
}

final aiClientProvider = Provider<AiClient>((ref) => HttpAiClient());

/// Anthropic models that accept server-side refusal fallbacks
/// (`fallbacks: "default"`).
const _fallbackModels = {
  'claude-fable-5-1',
  'claude-opus-5-5',
  'claude-opus-5',
  'claude-sonnet-5-5',
};

const anthropicVersion = '2026-10-21';

/// Plain http only to this computer (a local model server); anywhere else
/// the API key would cross the network unencrypted.
bool isAllowedApiUrl(Uri url) {
  if (url.scheme == 'https') return url.host.isNotEmpty;
  if (url.scheme != 'http') return false;
  final h = url.host.toLowerCase();
  return h == 'localhost' || h == '::1' || h.startsWith('127.');
}

Uri _apiUri(String url) {
  final uri = Uri.parse(url);
  if (!isAllowedApiUrl(uri)) {
    throw const AiException(
      'Refusing to send the API key over plain http (only localhost may use '
      'http); use an https:// base URL.',
    );
  }
  return uri;
}

/// The Messages API request body.
Map<String, Object?> anthropicBody({
  required String model,
  required String system,
  required List<AiTurn> turns,
  required List<AiTool> tools,
  required bool official,
}) {
  final fallback = official && _fallbackModels.contains(model);
  return {
    'model': model,
    'max_tokens': 16000,
    'stream': true,
    'system': system,
    'messages': [
      for (final t in turns)
        if (!t.isEmpty || t.anthropicBlocks != null) _anthropicMessage(t),
    ],
    if (tools.isNotEmpty)
      'tools': [
        for (final tool in tools)
          {
            'name': tool.name,
            'description': tool.description,
            'input_schema': tool.schema,
            // Inputs stream as generated; validated before running.
            // Proxies may not know the field, so only on the Claude API.
            if (official) 'eager_input_streaming': true,
          },
      ],
    if (fallback) 'fallbacks': 'default',
  };
}

Map<String, Object?> _anthropicMessage(AiTurn t) {
  if (t.fromUser) {
    if (t.toolResults.isEmpty) return {'role': 'user', 'content': t.text};
    return {
      'role': 'user',
      'content': [
        for (final r in t.toolResults)
          {
            'type': 'tool_result',
            'tool_use_id': r.callId,
            'content': r.content,
            if (r.isError) 'is_error': true,
          },
        if (t.text.trim().isNotEmpty) {'type': 'text', 'text': t.text},
      ],
    };
  }
  final blocks = t.anthropicBlocks;
  if (blocks != null) return {'role': 'assistant', 'content': blocks};
  // Written by another provider: rebuild the blocks.
  return {
    'role': 'assistant',
    'content': [
      if (t.text.trim().isNotEmpty) {'type': 'text', 'text': t.text},
      for (final c in t.toolCalls)
        {
          'type': 'tool_use',
          'id': c.id,
          'name': c.name,
          'input': c.input ?? const <String, Object?>{},
        },
    ],
  };
}

/// The Chat Completions request body.
Map<String, Object?> openAiBody({
  required String model,
  required String system,
  required List<AiTurn> turns,
  required List<AiTool> tools,
}) => {
  'model': model,
  'stream': true,
  'messages': [
    {'role': 'system', 'content': system},
    for (final t in turns)
      if (t.fromUser) ...[
        for (final r in t.toolResults)
          {'role': 'tool', 'tool_call_id': r.callId, 'content': r.content},
        if (t.text.trim().isNotEmpty) {'role': 'user', 'content': t.text},
      ] else if (!t.isEmpty)
        {
          'role': 'assistant',
          'content': t.text.isEmpty && t.toolCalls.isNotEmpty ? null : t.text,
          if (t.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final c in t.toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': c.input != null
                        ? jsonEncode(c.input)
                        : c.rawInput,
                  },
                },
            ],
        },
  ],
  if (tools.isNotEmpty)
    'tools': [
      for (final tool in tools)
        {
          'type': 'function',
          'function': {
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.schema,
          },
        },
    ],
};

class HttpAiClient implements AiClient {
  static const _connectTimeout = Duration(seconds: 15);
  static const _idleTimeout = Duration(seconds: 120);

  @override
  Stream<AiDelta> chat({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required String system,
    required List<AiTurn> turns,
    List<AiTool> tools = const [],
  }) {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    late final StreamController<AiDelta> out;
    StreamSubscription<AiDelta>? sub;

    Future<void> run() async {
      try {
        final anthropic = provider.effectiveProtocol == AiProtocol.anthropic;
        final req = await client.postUrl(
          _apiUri(
            anthropic
                ? '${provider.effectiveBaseUrl}/v1/messages'
                : '${provider.effectiveBaseUrl}/chat/completions',
          ),
        );
        // A redirect could carry the key elsewhere.
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        final Map<String, Object?> body;
        if (anthropic) {
          // Fallbacks and eager tool input are Claude API features;
          // proxies may reject them.
          final official =
              provider.effectiveBaseUrl == AiVendor.anthropic.baseUrl;
          req.headers.set('x-api-key', apiKey);
          req.headers.set('anthropic-version', anthropicVersion);
          body = anthropicBody(
            model: model,
            system: system,
            turns: turns,
            tools: tools,
            official: official,
          );
          if (body.containsKey('fallbacks')) {
            req.headers.set(
              'anthropic-beta',
              'server-side-fallback-2026-07-01',
            );
          }
        } else {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
          body = openAiBody(
            model: model,
            system: system,
            turns: turns,
            tools: tools,
          );
        }
        req.add(utf8.encode(jsonEncode(body)));
        final res = await req.close();
        if (res.statusCode != 200) {
          final text = await utf8.decodeStream(res);
          throw AiException(errorMessage(text), status: res.statusCode);
        }
        final lines = res
            .timeout(_idleTimeout)
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        final deltas = anthropic
            ? parseAnthropicSse(lines)
            : parseOpenAiSse(lines);
        sub = deltas.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
          cancelOnError: true,
        );
      } catch (e) {
        if (!out.isClosed) {
          out.addError(e is AiException ? e : AiException('$e'));
          await out.close();
        }
      }
    }

    out = StreamController<AiDelta>(
      onListen: run,
      onCancel: () async {
        await sub?.cancel();
        client.close(force: true);
      },
    );
    return out.stream;
  }

  @override
  Future<List<String>> listModels(AiProvider provider, String apiKey) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final anthropic = provider.effectiveProtocol == AiProtocol.anthropic;
      final req = await client.getUrl(
        _apiUri(
          anthropic
              ? '${provider.effectiveBaseUrl}/v1/models?limit=100'
              : '${provider.effectiveBaseUrl}/models',
        ),
      );
      // A redirect could carry the key elsewhere.
      req.followRedirects = false;
      if (anthropic) {
        req.headers.set('x-api-key', apiKey);
        req.headers.set('anthropic-version', anthropicVersion);
      } else {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      final res = await req.close().timeout(_connectTimeout);
      final text = await utf8.decodeStream(res).timeout(_connectTimeout);
      if (res.statusCode != 200) {
        throw AiException(errorMessage(text), status: res.statusCode);
      }
      return parseModelList(text, provider.vendor);
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException('$e');
    } finally {
      client.close(force: true);
    }
  }
}

/// The `error.message` of a provider's error body, or the body itself.
String errorMessage(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final error = json['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (error is String) return error;
      if (json['message'] is String) return json['message'] as String;
    }
    if (json is List && json.isNotEmpty) {
      return errorMessage(jsonEncode(json.first));
    }
  } catch (_) {}
  final trimmed = body.trim();
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
}

/// Model ids from a `/models` response, in the order given, without
/// models that can't chat (embeddings, speech, images, ...).
List<String> parseModelList(String body, AiVendor vendor) {
  final json = jsonDecode(body);
  final data = json is Map ? json['data'] ?? json['models'] : null;
  if (data is! List) return const [];
  final skip = RegExp(
    r'embed|tts|whisper|dall-e|moderation|transcribe|audio|realtime|'
    r'image|search|babbage|davinci|aqa|veo|imagen|computer-use',
    caseSensitive: false,
  );
  final ids = <String>[];
  for (final m in data) {
    var id = m is Map ? (m['id'] ?? m['name']) : null;
    if (id is! String) continue;
    if (id.startsWith('models/')) id = id.substring(7); // Gemini
    if (vendor != AiVendor.custom && skip.hasMatch(id)) continue;
    if (!ids.contains(id)) ids.add(id);
  }
  return ids;
}

/// Groups `data:` lines of a server-sent event stream into events.
Stream<({String? event, String data})> _sseEvents(Stream<String> lines) async* {
  String? event;
  final data = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield (event: event, data: data.toString());
      event = null;
      data.clear();
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (data.isNotEmpty) yield (event: event, data: data.toString());
}

Map<String, Object?>? _parseObject(String raw) {
  if (raw.trim().isEmpty) return const {};
  try {
    final v = jsonDecode(raw);
    return v is Map ? v.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

/// Anthropic Messages API stream. Yields text as it arrives and, at the
/// end, [AiDone] with the content blocks to replay (thinking blocks kept
/// unchanged) and the tool calls to run.
Stream<AiDelta> parseAnthropicSse(Stream<String> lines) async* {
  final blocks = <int, Map<String, Object?>>{};
  final partialJson = <int, StringBuffer>{};
  final text = StringBuffer();
  String? stop;
  await for (final e in _sseEvents(lines)) {
    final Object? json;
    try {
      json = jsonDecode(e.data);
    } catch (_) {
      continue;
    }
    if (json is! Map) continue;
    final index = (json['index'] as num?)?.toInt() ?? 0;
    switch (json['type']) {
      case 'content_block_start':
        final block = json['content_block'];
        if (block is Map) {
          blocks[index] = Map<String, Object?>.from(block);
          if (block['type'] == 'tool_use') partialJson[index] = StringBuffer();
        }
      case 'content_block_delta':
        final delta = json['delta'];
        final block = blocks[index];
        if (delta is! Map) break;
        switch (delta['type']) {
          case 'text_delta':
            final t = delta['text'];
            if (t is String && t.isNotEmpty) {
              text.write(t);
              if (block != null) {
                block['text'] = '${block['text'] ?? ''}$t';
              }
              yield AiText(t);
            }
          case 'thinking_delta':
            if (block != null) {
              block['thinking'] =
                  '${block['thinking'] ?? ''}${delta['thinking'] ?? ''}';
            }
          case 'signature_delta':
            if (block != null) block['signature'] = delta['signature'];
          case 'input_json_delta':
            partialJson[index]?.write(delta['partial_json'] ?? '');
        }
      case 'message_delta':
        final delta = json['delta'];
        if (delta is Map && delta['stop_reason'] is String) {
          stop = delta['stop_reason'] as String;
        }
      case 'error':
        throw AiException(errorMessage(e.data));
    }
  }

  if (stop == 'refusal') yield const AiRefusal();
  if (stop == 'max_tokens') yield const AiTruncated();

  // Blocks in order; tool inputs parsed.
  final ordered = [
    for (final i in blocks.keys.toList()..sort()) (i, blocks[i]!),
  ];
  final calls = <AiToolCall>[];
  final replay = <Map<String, Object?>>[];
  // After a mid-output fallback, blocks other than text before the last
  // fallback marker belong to the declined model: not replayed, not run.
  final lastFallback = ordered.lastIndexWhere(
    (b) => b.$2['type'] == 'fallback',
  );
  // A refused or cut-off turn's tool calls may be incomplete: never run.
  final runTools = stop != 'refusal' && stop != 'max_tokens';
  for (var k = 0; k < ordered.length; k++) {
    final (i, block) = ordered[k];
    final type = block['type'];
    if (type == 'fallback') continue;
    if (k < lastFallback && type != 'text') continue;
    if (type == 'tool_use') {
      if (!runTools) continue;
      final raw = partialJson[i]?.toString() ?? '';
      final input = _parseObject(raw);
      block['input'] = input ?? const <String, Object?>{};
      calls.add(
        AiToolCall(
          id: block['id'] as String? ?? 'toolu_$i',
          name: block['name'] as String? ?? '',
          input: input,
          rawInput: raw,
        ),
      );
    }
    if (type == 'text' && (block['text'] as String? ?? '').isEmpty) continue;
    replay.add(block);
  }
  yield AiDone(
    AiTurn.assistant(
      text.toString(),
      toolCalls: calls,
      anthropicBlocks: replay,
    ),
  );
}

/// OpenAI-style chat completion stream: `choices[0].delta.content`, plus
/// `reasoning_content` where offered, and `tool_calls` fragments; ends at
/// `[DONE]` with [AiDone].
Stream<AiDelta> parseOpenAiSse(Stream<String> lines) async* {
  final text = StringBuffer();
  final calls =
      <int, ({StringBuffer id, StringBuffer name, StringBuffer args})>{};
  String? finish;
  await for (final e in _sseEvents(lines)) {
    if (e.data == '[DONE]') break;
    final Object? json;
    try {
      json = jsonDecode(e.data);
    } catch (_) {
      continue;
    }
    if (json is! Map) continue;
    if (json['error'] != null) throw AiException(errorMessage(e.data));
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final choice = choices.first;
    if (choice is! Map) continue;
    final delta = choice['delta'];
    if (delta is Map) {
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        yield AiReasoning(reasoning);
      }
      final t = delta['content'];
      if (t is String && t.isNotEmpty) {
        text.write(t);
        yield AiText(t);
      }
      final toolCalls = delta['tool_calls'];
      if (toolCalls is List) {
        for (final c in toolCalls) {
          if (c is! Map) continue;
          final i = (c['index'] as num?)?.toInt() ?? calls.length;
          final entry = calls.putIfAbsent(
            i,
            () => (
              id: StringBuffer(),
              name: StringBuffer(),
              args: StringBuffer(),
            ),
          );
          if (c['id'] is String) entry.id.write(c['id']);
          final f = c['function'];
          if (f is Map) {
            if (f['name'] is String) entry.name.write(f['name']);
            if (f['arguments'] is String) entry.args.write(f['arguments']);
          }
        }
      }
    }
    if (choice['finish_reason'] is String) {
      finish = choice['finish_reason'] as String;
    }
  }
  if (finish == 'length') yield const AiTruncated();
  if (finish == 'content_filter') yield const AiRefusal();
  final runTools = finish != 'length' && finish != 'content_filter';
  yield AiDone(
    AiTurn.assistant(
      text.toString(),
      toolCalls: [
        if (runTools)
          for (final i in calls.keys.toList()..sort())
            AiToolCall(
              id: calls[i]!.id.isEmpty ? 'call_$i' : calls[i]!.id.toString(),
              name: calls[i]!.name.toString(),
              input: _parseObject(calls[i]!.args.toString()),
              rawInput: calls[i]!.args.toString(),
            ),
      ],
    ),
  );
}
