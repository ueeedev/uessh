import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/ai/ai_client.dart';
import 'package:uessh/features/ai/ai_config.dart';

Stream<String> _lines(String text) => Stream.fromIterable(text.split('\n'));

void main() {
  group('Anthropic stream', () {
    test('text deltas, refusal and truncation', () async {
      const sse = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_1"}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"x"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hel"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"lo"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}

event: message_stop
data: {"type":"message_stop"}
''';
      final out = await parseAnthropicSse(_lines(sse)).toList();
      expect(out.whereType<AiText>().map((d) => d.text).join(), 'Hello');
      expect(out.whereType<AiRefusal>(), hasLength(1));
    });

    test('an error event raises', () {
      const sse = '''
event: error
data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
''';
      expect(
        parseAnthropicSse(_lines(sse)).toList(),
        throwsA(
          isA<AiException>().having((e) => e.message, 'message', 'Overloaded'),
        ),
      );
    });
  });

  group('OpenAI-compatible stream', () {
    test('content, reasoning, [DONE]', () async {
      const sse = '''
data: {"choices":[{"delta":{"role":"assistant"}}]}

data: {"choices":[{"delta":{"reasoning_content":"think"}}]}

data: {"choices":[{"delta":{"content":"Hi"}}]}

data: {"choices":[{"delta":{"content":" there"},"finish_reason":"length"}]}

data: [DONE]

data: {"choices":[{"delta":{"content":"ignored"}}]}
''';
      final out = await parseOpenAiSse(_lines(sse)).toList();
      expect(out.whereType<AiText>().map((d) => d.text).join(), 'Hi there');
      expect(out.whereType<AiReasoning>().single.text, 'think');
      expect(out.whereType<AiTruncated>(), hasLength(1));
    });
  });

  test('model lists: chat models only, Gemini prefixes removed', () {
    expect(
      parseModelList(
        jsonEncode({
          'data': [
            {'id': 'gpt-x'},
            {'id': 'text-embedding-3'},
            {'id': 'whisper-1'},
            {'id': 'gpt-x'},
          ],
        }),
        AiVendor.openai,
      ),
      ['gpt-x'],
    );
    expect(
      parseModelList(
        jsonEncode({
          'data': [
            {'id': 'models/gemini-pro'},
          ],
        }),
        AiVendor.gemini,
      ),
      ['gemini-pro'],
    );
  });

  test('error bodies', () {
    expect(errorMessage('{"error":{"message":"bad key"}}'), 'bad key');
    expect(errorMessage('[{"error":{"message":"quota"}}]'), 'quota');
    expect(errorMessage('plain text'), 'plain text');
  });

  group('HTTP requests (local server)', () {
    late HttpServer server;
    late List<({String path, Map<String, String> headers, Object? body})> seen;
    late String Function(String path) respond;

    setUp(() async {
      seen = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final text = await utf8.decodeStream(req);
        final headers = <String, String>{};
        req.headers.forEach((k, v) => headers[k] = v.join(','));
        seen.add((
          path: req.uri.path,
          headers: headers,
          body: text.isEmpty ? null : jsonDecode(text),
        ));
        final out = respond(req.uri.path);
        if (out.startsWith('ERR')) {
          req.response.statusCode = 401;
          req.response.write('{"error":{"message":"invalid x-api-key"}}');
        } else {
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write(out);
        }
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    AiProvider custom(AiProtocol protocol) => AiProvider(
      id: 'c',
      vendor: AiVendor.custom,
      name: 'Local',
      baseUrl: 'http://127.0.0.1:${server.port}/api/',
      protocol: protocol,
    );

    test('Anthropic: /v1/messages with key and version headers', () async {
      respond = (_) =>
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\n';
      final out = await HttpAiClient()
          .chat(
            provider: custom(AiProtocol.anthropic),
            apiKey: 'sk-test',
            model: 'claude-opus-5-5',
            system: 'sys',
            turns: const [AiTurn.user('hi')],
          )
          .toList();
      expect(out.whereType<AiText>().single.text, 'ok');
      final r = seen.single;
      expect(r.path, '/api/v1/messages');
      expect(r.headers['x-api-key'], 'sk-test');
      expect(r.headers['anthropic-version'], anthropicVersion);
      // Not the official endpoint: no fallback beta.
      expect(r.headers.containsKey('anthropic-beta'), isFalse);
      final body = r.body! as Map;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['stream'], isTrue);
      expect(body['system'], 'sys');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(body.containsKey('fallbacks'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('OpenAI-compatible: /chat/completions with bearer token', () async {
      respond = (_) =>
          'data: {"choices":[{"delta":{"content":"yo"}}]}\n\ndata: [DONE]\n\n';
      final out = await HttpAiClient()
          .chat(
            provider: custom(AiProtocol.openai),
            apiKey: 'sk-test',
            model: 'm',
            system: 'sys',
            turns: const [
              AiTurn.user('hi'),
              AiTurn.assistant('a'),
              AiTurn.user('b'),
            ],
          )
          .toList();
      expect(out.whereType<AiText>().single.text, 'yo');
      final r = seen.single;
      expect(r.path, '/api/chat/completions');
      expect(r.headers['authorization'], 'Bearer sk-test');
      final messages = (r.body! as Map)['messages'] as List;
      expect(messages.first, {'role': 'system', 'content': 'sys'});
      expect(messages.map((m) => (m as Map)['role']), [
        'system',
        'user',
        'assistant',
        'user',
      ]);
    });

    test('HTTP errors carry the provider message', () async {
      respond = (_) => 'ERR';
      expect(
        HttpAiClient()
            .chat(
              provider: custom(AiProtocol.openai),
              apiKey: 'bad',
              model: 'm',
              system: '',
              turns: const [AiTurn.user('hi')],
            )
            .toList(),
        throwsA(
          isA<AiException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.message, 'message', 'invalid x-api-key'),
        ),
      );
      await expectLater(
        HttpAiClient().listModels(custom(AiProtocol.anthropic), 'bad'),
        throwsA(isA<AiException>()),
      );
    });

    test('model list request', () async {
      respond = (_) => '{"data":[{"id":"a"},{"id":"b"}]}';
      final models = await HttpAiClient().listModels(
        custom(AiProtocol.openai),
        'k',
      );
      expect(models, ['a', 'b']);
      expect(seen.single.path, '/api/models');
    });
  });
}
