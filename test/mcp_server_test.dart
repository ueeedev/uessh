import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/mcp/mcp_approval_dialog.dart';
import 'package:uessh/features/mcp/mcp_controller.dart';
import 'package:uessh/features/mcp/mcp_server.dart';
import 'package:uessh/features/mcp/mcp_tools.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

class _FakeMcpSession extends TerminalSession {
  _FakeMcpSession(Host host, TestEnv env, {SessionStatus? initialStatus})
    : super(
        host: host,
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      ) {
    status = initialStatus ?? SessionStatus.connected;
  }

  final ran = <String>[];
  String nextStdout = 'ok\n';
  String nextStderr = '';
  int nextExitCode = 0;

  @override
  Future<void> connect({bool auto = false}) async {
    status = SessionStatus.connected;
    notifyListeners();
  }

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
    if (nextStdout.isNotEmpty) onStdout?.call(nextStdout);
    if (nextStderr.isNotEmpty) onStderr?.call(nextStderr);
    return CommandResult(
      stdout: nextStdout,
      stderr: nextStderr,
      exitCode: nextExitCode,
    );
  }
}

class _FakeBackend implements McpBackend {
  _FakeBackend(this.env);

  final TestEnv env;
  @override
  bool vaultUnlocked = true;
  @override
  McpApprovalMode approvalMode = McpApprovalMode.readOnlyAuto;

  final _sessions = <_FakeMcpSession>[];
  _FakeMcpSession? _active;
  final savedHosts = <Host>[];
  final approvalRequests = <McpApprovalRequest>[];
  bool approveNext = true;

  void addSession(_FakeMcpSession s, {bool active = true}) {
    _sessions.add(s);
    if (active) _active = s;
  }

  @override
  List<TerminalSession> get sessions => _sessions;

  @override
  TerminalSession? get activeSession => _active;

  @override
  TerminalSession? sessionById(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<List<Host>> listHosts() async => savedHosts;

  @override
  TerminalSession openHost(Host host) {
    final s = _FakeMcpSession(host, env);
    addSession(s);
    return s;
  }

  @override
  TerminalSession openLocal() {
    final s = _FakeMcpSession(localHost(), env);
    addSession(s);
    return s;
  }

  @override
  Future<bool> requestApproval(McpApprovalRequest request) async {
    approvalRequests.add(request);
    return approveNext;
  }

  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
  }
}

Host _testHost({String id = 'srv-1', String label = 'prod-web'}) => Host(
  id: id,
  label: label,
  address: '10.0.0.10',
  port: 22,
  username: 'deploy',
  authMethod: AuthMethod.password,
  groupId: 'prod',
);

class _RealHttpOverrides extends HttpOverrides {}

HttpClient _realHttpClient() => HttpOverrides.runWithHttpOverrides(
  () => HttpClient(),
  _RealHttpOverrides(),
);

Future<(int, HttpHeaders, String)> _httpPost(
  int port,
  String path,
  Object body, {
  String? token,
  String? hostHeader,
  String? originHeader,
}) async {
  // Bypass TestWidgetsFlutterBinding's mock HttpOverrides for loopback tests.
  final client = _realHttpClient();
  try {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (hostHeader != null) {
      req.headers.set(HttpHeaders.hostHeader, hostHeader);
    }
    if (originHeader != null) {
      req.headers.set('origin', originHeader);
    }
    req.headers.contentType = ContentType.json;
    req.write(body is String ? body : jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    return (res.statusCode, res.headers, text);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('MCP protocol & security', () {
    late TestEnv env;
    late _FakeBackend backend;
    late McpServer server;
    const token = 'test-secret-token-1234567890';

    setUp(() async {
      env = TestEnv();
      backend = _FakeBackend(env);
      backend.savedHosts.add(_testHost());
      final session = _FakeMcpSession(_testHost(), env);
      session.terminal.write('deploy@prod-web:~\$ ');
      backend.addSession(session);
      server = McpServer(executor: McpToolExecutor(backend), token: token);
      await server.start(0);
    });

    tearDown(() async {
      await server.stop();
      backend.dispose();
      env.dispose();
    });

    test(
      'rejects missing/wrong token, non-loopback host, and foreign origin',
      () async {
        final p = server.port!;

        final (s1, _, _) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        });
        expect(s1, HttpStatus.unauthorized);

        final (s2, _, _) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        }, token: 'wrong-token');
        expect(s2, HttpStatus.unauthorized);

        final (s3, _, _) = await _httpPost(
          p,
          '/mcp',
          {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          token: token,
          hostHeader: 'evil.example.com',
        );
        expect(s3, HttpStatus.forbidden);

        final (s4, _, _) = await _httpPost(
          p,
          '/mcp',
          {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
          token: token,
          originHeader: 'https://evil.example.com',
        );
        expect(s4, HttpStatus.forbidden);
      },
    );

    test(
      'Streamable HTTP: initialize, notifications, tools/list, tools/call',
      () async {
        final p = server.port!;

        final (sInit, headers, bodyInit) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': '2025-03-26'},
        }, token: token);
        expect(sInit, HttpStatus.ok);
        expect(headers.value('mcp-session-id'), isNotEmpty);
        final initJson = jsonDecode(bodyInit) as Map<String, dynamic>;
        expect(initJson['result']['protocolVersion'], '2025-03-26');
        expect(initJson['result']['serverInfo']['name'], 'uessh');

        // Notification returns 202 Accepted with no body.
        final (sNotif, _, bodyNotif) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, token: token);
        expect(sNotif, HttpStatus.accepted);
        expect(bodyNotif, isEmpty);

        // tools/list returns all 5 tools.
        final (sList, _, bodyList) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
        }, token: token);
        expect(sList, HttpStatus.ok);
        final tools = ((jsonDecode(bodyList) as Map)['result']['tools'] as List)
            .map((t) => (t as Map)['name'])
            .toSet();
        expect(
          tools,
          containsAll([
            'list_sessions',
            'list_hosts',
            'open_session',
            'run_command',
            'read_terminal',
          ]),
        );
      },
    );

    test('run_command executes read-only command and renders output in terminal', () async {
      final p = server.port!;
      final session = backend.activeSession! as _FakeMcpSession;
      session.nextStdout = 'Linux prod-web 6.8.0\n';

      final (status, _, body) = await _httpPost(p, '/mcp', {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'run_command',
          'arguments': {'command': 'uname -a'},
        },
      }, token: token);

      expect(status, HttpStatus.ok);
      expect(backend.approvalRequests, isEmpty, reason: 'read-only auto-runs');
      expect(session.ran, ['uname -a']);

      final result = (jsonDecode(body) as Map)['result'] as Map;
      expect(result['isError'], isNull);
      final text = ((result['content'] as List).first as Map)['text'] as String;
      expect(text, contains('exit code: 0'));
      expect(text, contains('Linux prod-web 6.8.0'));

      // The terminal itself displays the MCP box, command, output, and prompt.
      final screen = session.terminal.buffer.getText();
      expect(screen, contains('UESSH MCP'));
      expect(screen, contains('uname -a'));
      expect(screen, contains('Linux prod-web 6.8.0'));
      expect(screen, contains('exit 0'));
    });

    test('modifying commands require approval under readOnlyAuto and respect denial', () async {
      final p = server.port!;
      final session = backend.activeSession! as _FakeMcpSession;
      backend.approveNext = false;

      final (status, _, body) = await _httpPost(p, '/mcp', {
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {
          'name': 'run_command',
          'arguments': {
            'command': 'touch /tmp/mcp-test',
            'purpose': 'create marker',
          },
        },
      }, token: token);

      expect(status, HttpStatus.ok);
      expect(backend.approvalRequests.length, 1);
      final req = backend.approvalRequests.single as McpCommandApproval;
      expect(req.command, 'touch /tmp/mcp-test');
      expect(req.purpose, 'create marker');
      expect(req.readOnly, isFalse);
      expect(session.ran, isEmpty);

      final result = (jsonDecode(body) as Map)['result'] as Map;
      expect(result['isError'], isTrue);

      // Approving lets it execute and show in terminal.
      backend.approveNext = true;
      final (_, _, body2) = await _httpPost(p, '/mcp', {
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {
          'name': 'run_command',
          'arguments': {'command': 'touch /tmp/mcp-test'},
        },
      }, token: token);
      expect(session.ran, ['touch /tmp/mcp-test']);
      expect(((jsonDecode(body2) as Map)['result'] as Map)['isError'], isNull);
    });

    test(
      'askAll prompts even for read-only commands and read_terminal',
      () async {
        backend.approvalMode = McpApprovalMode.askAll;
        backend.approveNext = false;
        final p = server.port!;

        final (_, _, cmdBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'tools/call',
          'params': {
            'name': 'run_command',
            'arguments': {'command': 'ls -la'},
          },
        }, token: token);
        expect(
          ((jsonDecode(cmdBody) as Map)['result'] as Map)['isError'],
          isTrue,
        );
        expect(backend.approvalRequests.last, isA<McpCommandApproval>());

        final (_, _, readBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/call',
          'params': {
            'name': 'read_terminal',
            'arguments': {'lines': 20},
          },
        }, token: token);
        expect(
          ((jsonDecode(readBody) as Map)['result'] as Map)['isError'],
          isTrue,
        );
        expect(backend.approvalRequests.last, isA<McpReadTerminalApproval>());
      },
    );

    test(
      'list_sessions, list_hosts, open_session, and read_terminal work',
      () async {
        final p = server.port!;

        final (_, _, sessionsBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 8,
          'method': 'tools/call',
          'params': {'name': 'list_sessions'},
        }, token: token);
        final sessionsText =
            ((((jsonDecode(sessionsBody) as Map)['result'] as Map)['content']
                            as List)
                        .first
                    as Map)['text']
                as String;
        expect(sessionsText, contains('prod-web'));
        expect(sessionsText, contains('"is_active": true'));

        final (_, _, hostsBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 9,
          'method': 'tools/call',
          'params': {'name': 'list_hosts'},
        }, token: token);
        final hostsText =
            ((((jsonDecode(hostsBody) as Map)['result'] as Map)['content']
                            as List)
                        .first
                    as Map)['text']
                as String;
        expect(hostsText, contains('srv-1'));
        expect(hostsText, contains('10.0.0.10'));

        // open_session reuses existing connected session by default.
        final (_, _, openBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 10,
          'method': 'tools/call',
          'params': {
            'name': 'open_session',
            'arguments': {'host_id': 'srv-1'},
          },
        }, token: token);
        final openText =
            ((((jsonDecode(openBody) as Map)['result'] as Map)['content']
                            as List)
                        .first
                    as Map)['text']
                as String;
        expect(openText, contains('"reused": true'));

        // read_terminal returns terminal contents.
        final (_, _, readBody) = await _httpPost(p, '/mcp', {
          'jsonrpc': '2.0',
          'id': 11,
          'method': 'tools/call',
          'params': {
            'name': 'read_terminal',
            'arguments': {'lines': 20},
          },
        }, token: token);
        final readText =
            ((((jsonDecode(readBody) as Map)['result'] as Map)['content']
                            as List)
                        .first
                    as Map)['text']
                as String;
        expect(readText, contains('deploy@prod-web'));
      },
    );

    test('locked vault refuses all MCP tool calls', () async {
      backend.vaultUnlocked = false;
      final (_, _, body) = await _httpPost(server.port!, '/mcp', {
        'jsonrpc': '2.0',
        'id': 12,
        'method': 'tools/call',
        'params': {'name': 'list_sessions'},
      }, token: token);
      final result = (jsonDecode(body) as Map)['result'] as Map;
      expect(result['isError'], isTrue);
      expect(
        ((result['content'] as List).first as Map)['text'],
        contains('vault is locked'),
      );
    });

    test(
      'legacy HTTP+SSE transport streams endpoint and JSON-RPC responses',
      () async {
        final p = server.port!;
        final client = _realHttpClient();
        try {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:$p/sse'));
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final res = await req.close();
          expect(res.statusCode, HttpStatus.ok);

          final endpoint = Completer<String>();
          final reply = Completer<String>();
          var currentEvent = '';
          final sub = res
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen((line) {
                if (line.startsWith('event: ')) {
                  currentEvent = line.substring(7);
                } else if (line.startsWith('data: ')) {
                  final data = line.substring(6);
                  if (currentEvent == 'endpoint' && !endpoint.isCompleted) {
                    endpoint.complete(data);
                  } else if (currentEvent == 'message' && !reply.isCompleted) {
                    reply.complete(data);
                  }
                }
              });

          final msgPath = await endpoint.future.timeout(
            const Duration(seconds: 5),
          );
          expect(msgPath, startsWith('/messages?sessionId='));

          final (postStatus, _, _) = await _httpPost(p, msgPath, {
            'jsonrpc': '2.0',
            'id': 99,
            'method': 'ping',
          }, token: token);
          expect(postStatus, HttpStatus.accepted);

          final msg = await reply.future.timeout(const Duration(seconds: 5));
          final decoded = jsonDecode(msg) as Map<String, dynamic>;
          expect(decoded['id'], 99);
          expect(decoded['result'], isA<Map>());
          await sub.cancel();
        } finally {
          client.close(force: true);
        }
      },
    );
  });

  group('MCP UI & settings', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    testWidgets(
      'enabling MCP in settings starts server and stores token in vault',
      (tester) async {
        // Pick a free port so tests never collide with a running uessh instance.
        final freePort = (await tester.runAsync(() async {
          final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
          final p = s.port;
          await s.close();
          return p;
        }))!;
        env.settings = AppSettings(
          language: AppLanguage.zh,
          mcpEnabled: false,
          mcpPort: freePort,
        );
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(overrides: env.overrides, child: const UesshApp()),
        );
        await settleIo(tester);

        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        await selectSettingsCategory(tester, SettingsCategory.mcp);

        final toggle = find.byKey(const ValueKey('mcp-enable'));
        await scrollTo(tester, toggle);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

        await tester.tap(toggle);
        await settleIo(tester);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(UesshApp)),
        );
        final mcp = container.read(mcpControllerProvider);
        expect(mcp.running, isTrue);
        expect(mcp.port, freePort);
        expect(mcp.token, isNotNull);

        // Token is stored in the encrypted vault, never in settings.json.
        final vaultToken = await tester.runAsync(
          () => env.secrets.read(mcpTokenSecretKey),
        );
        expect(vaultToken, mcp.token);
        final settingsFile = File('${env.dataDir.path}/settings.json');
        expect(settingsFile.readAsStringSync(), isNot(contains(mcp.token!)));

        // Cleanly turn off before teardown.
        await tester.tap(toggle);
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(container.read(mcpControllerProvider).running, isFalse);
      },
    );

    testWidgets(
      'approval dialog warns on hidden characters and returns user choice',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(overrides: env.overrides, child: const UesshApp()),
        );
        await settleIo(tester);

        final future = showMcpApprovalDialog(
          const McpCommandApproval(
            command: 'rm \u202E/tmp/x',
            hostLabel: 'prod-web (deploy@10.0.0.10:22)',
            readOnly: false,
            purpose: 'cleanup',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('mcp-approval-dialog')),
          findsOneWidget,
        );
        expect(find.textContaining('<U+202E>'), findsOneWidget);
        expect(find.textContaining('cleanup'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('mcp-approve-deny')));
        await tester.pumpAndSettle();
        expect(await future, isFalse);
      },
    );
  });
}
