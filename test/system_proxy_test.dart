import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/core/app_providers.dart';
import 'package:uessh/core/proxy_settings.dart';
import 'package:uessh/core/proxy_transport.dart';
import 'package:uessh/core/system_proxy.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/settings/proxy_settings_card.dart';

import 'test_helpers.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  group('macOS scutil --proxy parser', () {
    test('parses HTTP/HTTPS/SOCKS5 proxy and ExceptionsList', () {
      const sample = '''
<dictionary> {
  ExceptionsList : <array> {
    0 : *zhihu.com
    1 : localhost
    2 : *.local
    3 : 127.*
    4 : 192.168.0.0/16
  }
  FTPPassive : 1
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7891
  SOCKSProxy : 127.0.0.1
}
''';
      final cfg = parseMacOsScutilProxy(sample);
      expect(cfg.httpProxy, '127.0.0.1:7890');
      expect(cfg.httpsProxy, '127.0.0.1:7890');
      expect(cfg.socksProxy, '127.0.0.1:7891');
      expect(
        cfg.resolveFor(Uri.parse('https://api.deepseek.com/chat/completions')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(cfg.resolveForTcp('1.2.3.4'), (
        host: '127.0.0.1',
        port: 7891,
        isSocks5: true,
      ));
      // ExceptionsList & loopback bypass the proxy.
      expect(cfg.resolveFor(Uri.parse('https://www.zhihu.com')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://nas.local:8080')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://192.168.1.50:8000')), 'DIRECT');
      expect(cfg.resolveForTcp('192.168.1.50'), isNull);
      expect(cfg.resolveFor(Uri.parse('http://127.0.0.1:11434')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://localhost:11434')), 'DIRECT');
    });

    test('returns direct when all proxies are disabled', () {
      const disabled = '''
<dictionary> {
  HTTPEnable : 0
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 0
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 0
  SOCKSPort : 7890
  SOCKSProxy : 127.0.0.1
}
''';
      final cfg = parseMacOsScutilProxy(disabled);
      expect(cfg.hasProxy, isFalse);
      expect(cfg.resolveFor(Uri.parse('https://api.deepseek.com')), 'DIRECT');
      expect(cfg.resolveForTcp('example.com'), isNull);
    });
  });

  group('Windows reg query parser', () {
    test('parses single ProxyServer and ProxyOverride including <local>', () {
      const sample = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7890
    ProxyOverride    REG_SZ    localhost;127.*;10.*;192.168.*;*.corp.internal;<local>
''';
      final cfg = parseWindowsRegProxy(sample);
      expect(cfg.httpProxy, '127.0.0.1:7890');
      expect(cfg.httpsProxy, '127.0.0.1:7890');
      expect(
        cfg.resolveFor(Uri.parse('https://api.anthropic.com/v1/messages')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(cfg.resolveForTcp('example.com'), (
        host: '127.0.0.1',
        port: 7890,
        isSocks5: false,
      ));
      expect(cfg.resolveFor(Uri.parse('https://git.corp.internal')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://intranet:8080')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://10.0.0.5:8080')), 'DIRECT');
    });

    test('parses per-protocol ProxyServer including socks and ignores off', () {
      const perProto = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    http=127.0.0.1:8080;https=http://127.0.0.1:8443;socks=127.0.0.1:1080
''';
      final cfg = parseWindowsRegProxy(perProto);
      expect(cfg.httpProxy, '127.0.0.1:8080');
      expect(cfg.httpsProxy, '127.0.0.1:8443');
      expect(cfg.socksProxy, '127.0.0.1:1080');
      expect(
        cfg.resolveFor(Uri.parse('http://example.com')),
        'PROXY 127.0.0.1:8080; DIRECT',
      );
      expect(
        cfg.resolveFor(Uri.parse('https://example.com')),
        'PROXY 127.0.0.1:8443; DIRECT',
      );
      expect(cfg.resolveForTcp('example.com'), (
        host: '127.0.0.1',
        port: 1080,
        isSocks5: true,
      ));

      const off = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x0
    ProxyServer    REG_SZ    127.0.0.1:7890
''';
      expect(parseWindowsRegProxy(off).hasProxy, isFalse);
    });
  });

  group('SystemProxyResolver', () {
    test(
      'prefers explicit env proxy, falls back to OS proxy, caches by TTL',
      () {
        var loads = 0;
        var now = DateTime(2026, 11, 25, 10, 0, 0);
        var env = <String, String>{};
        var osProxy = const SystemProxyConfig(
          httpProxy: '127.0.0.1:7890',
          httpsProxy: '127.0.0.1:7890',
        );

        final resolver = SystemProxyResolver(
          ttl: const Duration(seconds: 5),
          loadSystemProxy: () {
            loads++;
            return osProxy;
          },
          readEnvironment: () => env,
          now: () => now,
        );

        expect(
          resolver.findProxy(Uri.parse('https://api.deepseek.com')),
          'PROXY 127.0.0.1:7890; DIRECT',
        );
        expect(loads, 1);

        now = now.add(const Duration(seconds: 3));
        expect(
          resolver.findProxy(Uri.parse('https://api.openai.com')),
          'PROXY 127.0.0.1:7890; DIRECT',
        );
        expect(loads, 1);

        now = now.add(const Duration(seconds: 3));
        osProxy = SystemProxyConfig.direct;
        expect(
          resolver.findProxy(Uri.parse('https://api.openai.com')),
          'DIRECT',
        );
        expect(loads, 2);

        env = {'HTTPS_PROXY': 'http://127.0.0.1:9999'};
        expect(
          resolver.findProxy(Uri.parse('https://api.deepseek.com')),
          'PROXY 127.0.0.1:9999',
        );
        expect(
          resolver.findProxy(Uri.parse('http://127.0.0.1:11434/v1/models')),
          'DIRECT',
        );
      },
    );
  });

  group('proxy transport (HTTP CONNECT & SOCKS5)', () {
    test(
      'HTTP CONNECT sends Basic auth and preserves trailing SSH banner bytes',
      () async {
        String? receivedRequest;
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((client) {
          final buf = <int>[];
          client.listen((chunk) {
            buf.addAll(chunk);
            final text = latin1.decode(buf);
            if (receivedRequest == null && text.contains('\r\n\r\n')) {
              receivedRequest = text;
              // Send 200 OK AND the target SSH banner in a single write to
              // verify leftover handshake bytes are never dropped.
              client.add(
                ascii.encode(
                  'HTTP/1.1 200 Connection Established\r\n\r\nSSH-2.0-Test\r\n',
                ),
              );
            } else if (receivedRequest != null) {
              client.add(chunk); // echo subsequent payloads
            }
          });
        });

        final ssh = await connectSshViaHttpConnect(
          proxyHost: '127.0.0.1',
          proxyPort: server.port,
          targetHost: 'prod.example.com',
          targetPort: 2222,
          username: 'alice',
          password: 'secret',
        );
        addTearDown(ssh.destroy);

        expect(
          receivedRequest,
          contains('CONNECT prod.example.com:2222 HTTP/1.1'),
        );
        final expectedAuth = base64Encode(utf8.encode('alice:secret'));
        expect(
          receivedRequest,
          contains('Proxy-Authorization: Basic $expectedAuth'),
        );

        final received = StringBuffer();
        final gotBanner = Completer<void>();
        final gotEcho = Completer<void>();
        final sub = ssh.stream.listen((chunk) {
          received.write(ascii.decode(chunk));
          if (!gotBanner.isCompleted &&
              received.toString().contains('SSH-2.0-Test\r\n')) {
            gotBanner.complete();
          }
          if (!gotEcho.isCompleted && received.toString().contains('PING')) {
            gotEcho.complete();
          }
        });
        addTearDown(sub.cancel);

        await gotBanner.future.timeout(const Duration(seconds: 5));
        ssh.sink.add(ascii.encode('PING'));
        await gotEcho.future.timeout(const Duration(seconds: 5));
      },
    );

    test('SOCKS5 performs RFC 1929 username/password auth and preserves banner bytes', () async {
      String? authedUser;
      String? authedPass;
      String? targetHostSeen;
      int? targetPortSeen;

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((client) {
        var stage = 0;
        final buf = <int>[];
        client.listen((chunk) {
          if (stage == 3) {
            client.add(chunk);
            return;
          }
          buf.addAll(chunk);
          if (stage == 0 && buf.length >= 2 && buf.length >= 2 + buf[1]) {
            expect(buf[0], 0x05);
            expect(buf.sublist(2, 2 + buf[1]), contains(0x02));
            buf.removeRange(0, 2 + buf[1]);
            stage = 1;
            client.add(const [0x05, 0x02]); // require username/password
          }
          if (stage == 1 && buf.length >= 2) {
            final ulen = buf[1];
            if (buf.length >= 2 + ulen + 1) {
              final plen = buf[2 + ulen];
              if (buf.length >= 3 + ulen + plen) {
                authedUser = utf8.decode(buf.sublist(2, 2 + ulen));
                authedPass = utf8.decode(
                  buf.sublist(3 + ulen, 3 + ulen + plen),
                );
                buf.removeRange(0, 3 + ulen + plen);
                stage = 2;
                client.add(const [0x01, 0x00]); // auth succeeded
              }
            }
          }
          if (stage == 2 && buf.length >= 5) {
            expect(buf[0], 0x05);
            expect(buf[1], 0x01); // CONNECT
            expect(buf[3], 0x03); // DOMAINNAME
            final dlen = buf[4];
            if (buf.length >= 5 + dlen + 2) {
              targetHostSeen = utf8.decode(buf.sublist(5, 5 + dlen));
              targetPortSeen = (buf[5 + dlen] << 8) | buf[6 + dlen];
              buf.removeRange(0, 5 + dlen + 2);
              stage = 3;
              // Reply + SSH banner in the same packet.
              client.add([
                0x05,
                0x00,
                0x00,
                0x01,
                127,
                0,
                0,
                1,
                0,
                22,
                ...ascii.encode('SSH-2.0-SocksOK\r\n'),
              ]);
            }
          }
        });
      });

      final ssh = await connectSshViaSocks5(
        proxyHost: '127.0.0.1',
        proxyPort: server.port,
        targetHost: 'bastion.example.com',
        targetPort: 22,
        username: 'bob',
        password: 'pw!',
      );
      addTearDown(ssh.destroy);

      expect(authedUser, 'bob');
      expect(authedPass, 'pw!');
      expect(targetHostSeen, 'bastion.example.com');
      expect(targetPortSeen, 22);

      final first = await ssh.stream.first.timeout(const Duration(seconds: 5));
      expect(ascii.decode(first), 'SSH-2.0-SocksOK\r\n');
    });

    test('HttpClient routes through custom SOCKS5 proxy via connectionFactory', () async {
      // Minimal HTTP origin behind a minimal no-auth SOCKS5 proxy.
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(origin.close);
      origin.listen((req) {
        req.response
          ..statusCode = 200
          ..write('proxied-http-ok')
          ..close();
      });

      final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socks.close);
      socks.listen((client) {
        var stage = 0;
        final buf = <int>[];
        Socket? upstream;
        client.listen(
          (chunk) async {
            if (stage == 2) {
              upstream?.add(chunk);
              return;
            }
            buf.addAll(chunk);
            if (stage == 0 && buf.length >= 3) {
              buf.removeRange(0, 2 + buf[1]);
              stage = 1;
              client.add(const [0x05, 0x00]);
            }
            if (stage == 1 && buf.length >= 7) {
              final dlen = buf[4];
              if (buf.length >= 5 + dlen + 2) {
                final port = (buf[5 + dlen] << 8) | buf[6 + dlen];
                buf.removeRange(0, 5 + dlen + 2);
                stage = 2;
                upstream = await Socket.connect(
                  InternetAddress.loopbackIPv4,
                  port,
                );
                upstream!.listen(
                  client.add,
                  onDone: client.close,
                  onError: (_) => client.destroy(),
                );
                client.add(const [0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
                if (buf.isNotEmpty) {
                  upstream!.add(buf);
                  buf.clear();
                }
              }
            }
          },
          onDone: () => upstream?.close(),
          onError: (_) => upstream?.destroy(),
        );
      });

      // Bypass Flutter's test HTTP mock so real loopback SOCKS5 sockets run.
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        configureHttpClientProxy(
          client,
          proxy: ProxySettings(
            mode: ProxyMode.custom,
            scheme: ProxyScheme.socks5,
            host: '127.0.0.1',
            port: socks.port,
          ),
        );
        // Use a non-loopback hostname so loopback bypass does not skip SOCKS5;
        // our mock SOCKS5 server connects to loopback on the target port.
        final req = await client.getUrl(
          Uri.parse('http://fake-ai.test:${origin.port}/v1/models'),
        );
        final res = await req.close().timeout(const Duration(seconds: 5));
        final body = await utf8.decodeStream(res);
        expect(res.statusCode, 200);
        expect(body, 'proxied-http-ok');
      }, _RealHttpOverrides());
    });
  });

  group('SettingsPage network proxy UI', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    testWidgets(
      'configures AI and SSH proxies separately and stores passwords in vault only',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...env.overrides,
              systemProxyInspectorProvider.overrideWithValue(
                () => const SystemProxyConfig(
                  httpProxy: '127.0.0.1:7890',
                  httpsProxy: '127.0.0.1:7890',
                  socksProxy: '127.0.0.1:7891',
                ),
              ),
            ],
            child: const UesshApp(),
          ),
        );
        await settleIo(tester);

        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();

        await selectSettingsCategory(tester, SettingsCategory.proxy);
        expect(find.text('网络代理'), findsWidgets);
        await scrollTo(
          tester,
          find.byKey(const ValueKey('proxy-settings-card')),
        );
        expect(find.text('AI 网络代理'), findsOneWidget);
        expect(find.text('SSH 网络代理'), findsOneWidget);
        // AI defaults to System and shows detected OS proxy.
        expect(find.text('已检测到系统代理：http://127.0.0.1:7890'), findsOneWidget);

        // Configure custom HTTP proxy + password for AI.
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('ai-proxy-mode')),
            matching: find.text('自定义'),
          ),
        );
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byKey(const ValueKey('ai-proxy-save')));
        await tester.enterText(
          find.byKey(const ValueKey('ai-proxy-host')),
          '127.0.0.1',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ai-proxy-port')),
          '7899',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ai-proxy-user')),
          'aiuser',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ai-proxy-pass')),
          'top-secret-ai-pass',
        );
        await tester.ensureVisible(find.byKey(const ValueKey('ai-proxy-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-proxy-save')));
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(find.text('http://127.0.0.1:7899'), findsOneWidget);

        // Configure custom SOCKS5 proxy for SSH.
        await scrollTo(tester, find.byKey(const ValueKey('ssh-proxy-mode')));
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('ssh-proxy-mode')),
            matching: find.text('自定义'),
          ),
        );
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byKey(const ValueKey('ssh-proxy-save')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('ssh-proxy-scheme')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ssh-proxy-scheme')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SOCKS5').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('ssh-proxy-host')),
          '10.0.0.2',
        );
        await tester.enterText(
          find.byKey(const ValueKey('ssh-proxy-port')),
          '1080',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('ssh-proxy-save')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ssh-proxy-save')));
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(find.text('socks5://10.0.0.2:1080'), findsOneWidget);

        // Verify persistence and that proxy password went to vault, not settings.json.
        final rawSettings = await tester.runAsync(
          () => File('${env.dataDir.path}/settings.json').readAsString(),
        );
        expect(rawSettings, isNot(contains('top-secret-ai-pass')));
        final loaded = (await tester.runAsync(
          () => SettingsStore(dataDir: env.dataDir).load(),
        ))!;
        expect(loaded.aiProxy.mode, ProxyMode.custom);
        expect(loaded.aiProxy.scheme, ProxyScheme.http);
        expect(loaded.aiProxy.host, '127.0.0.1');
        expect(loaded.aiProxy.port, 7899);
        expect(loaded.aiProxy.username, 'aiuser');
        expect(loaded.sshProxy.mode, ProxyMode.custom);
        expect(loaded.sshProxy.scheme, ProxyScheme.socks5);
        expect(loaded.sshProxy.host, '10.0.0.2');
        expect(loaded.sshProxy.port, 1080);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(UesshApp)),
        );
        expect(
          container.read(vaultProvider).read(aiProxyPasswordKey),
          'top-secret-ai-pass',
        );
      },
    );
  });
}
