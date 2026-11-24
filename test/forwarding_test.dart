import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/forwarding/forwarding_providers.dart';
import 'package:uessh/features/forwarding/port_forward.dart';
import 'package:uessh/features/forwarding/tunnel_engine.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';

import 'test_helpers.dart';

/// Adapts a real loopback [Socket] into an [SSHForwardChannel] so tunnel tests
/// push actual TCP bytes through local, remote, and SOCKS5 forwarders.
class _SocketAsForwardChannel implements SSHForwardChannel {
  _SocketAsForwardChannel(this._socket) {
    _stream = _socket.asBroadcastStream();
  }

  final Socket _socket;
  late final Stream<Uint8List> _stream;

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();
}

class _FakeRemoteForwardHandle implements RemoteForwardHandle {
  _FakeRemoteForwardHandle({required this.host, required this.port});

  @override
  final String host;

  @override
  final int port;

  final controller = StreamController<SSHForwardChannel>();
  bool closed = false;

  @override
  Stream<SSHForwardChannel> get connections => controller.stream;

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

/// Loopback [ForwardTransport] that dials real TCP targets for `-L` / `-D` and
/// simulates remote listener registration for `-R`.
class _LoopbackForwardTransport implements ForwardTransport {
  _LoopbackForwardTransport({this.rejectRemote = false});

  final bool rejectRemote;
  final _done = Completer<void>();
  bool closed = false;
  _FakeRemoteForwardHandle? lastRemote;

  void simulateDrop() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    final socket = await Socket.connect(remoteHost, remotePort);
    return _SocketAsForwardChannel(socket);
  }

  @override
  Future<RemoteForwardHandle?> forwardRemote({String? host, int? port}) async {
    if (rejectRemote) return null;
    final assigned = (port == null || port == 0) ? 45123 : port;
    lastRemote = _FakeRemoteForwardHandle(
      host: host ?? '127.0.0.1',
      port: assigned,
    );
    return lastRemote;
  }

  @override
  Future<void> get done => _done.future;

  @override
  void close() {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }
}

/// Starts a loopback TCP echo server and returns `(server, port)`.
Future<ServerSocket> _startEchoServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((client) {
    client.listen(
      client.add,
      onDone: () => client.close(),
      onError: (_) => client.destroy(),
    );
  });
  return server;
}

const _sampleHost = Host(
  id: 'h1',
  label: 'prod-db',
  address: '10.0.0.10',
  port: 2222,
  username: 'ops',
  authMethod: AuthMethod.password,
);

void main() {
  group('port forward model & repository', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    test(
      'persists local, remote, and dynamic rules to forwards.json',
      () async {
        final repo = PortForwardRepository(dataDir: env.dataDir);
        final rules = [
          const PortForwardRule(
            id: 'f1',
            name: 'Prod MySQL',
            type: ForwardType.local,
            hostId: 'h1',
            bindHost: '127.0.0.1',
            bindPort: 13306,
            targetHost: '127.0.0.1',
            targetPort: 3306,
            autoStart: true,
            note: 'Read replica',
          ),
          const PortForwardRule(
            id: 'f2',
            type: ForwardType.remote,
            hostId: 'h1',
            bindHost: '0.0.0.0',
            bindPort: 9000,
            targetHost: '127.0.0.1',
            targetPort: 3000,
          ),
          const PortForwardRule(
            id: 'f3',
            name: 'Office SOCKS5',
            type: ForwardType.dynamic,
            hostId: 'h1',
            bindHost: '127.0.0.1',
            bindPort: 1080,
          ),
        ];

        await repo.save(rules);
        final loaded = await repo.load();
        expect(loaded.length, 3);
        expect(loaded[0].name, 'Prod MySQL');
        expect(loaded[0].type, ForwardType.local);
        expect(loaded[0].bindPort, 13306);
        expect(loaded[0].targetPort, 3306);
        expect(loaded[0].autoStart, isTrue);
        expect(loaded[0].note, 'Read replica');

        expect(loaded[1].type, ForwardType.remote);
        expect(loaded[1].displayName, '0.0.0.0:9000 → 127.0.0.1:3000');
        expect(loaded[1].copyableAddress(), '127.0.0.1:9000');

        expect(loaded[2].type, ForwardType.dynamic);
        expect(loaded[2].copyableAddress(), 'socks5://127.0.0.1:1080');
        expect(
          loaded[0].sshCommandPreview(_sampleHost),
          'ssh -N -p 2222 -L 127.0.0.1:13306:127.0.0.1:3306 ops@10.0.0.10',
        );
        expect(
          loaded[2].sshCommandPreview(_sampleHost),
          'ssh -N -p 2222 -D 127.0.0.1:1080 ops@10.0.0.10',
        );
      },
    );

    test('formats transfer byte counts cleanly', () {
      expect(formatTransferBytes(512), '512 B');
      expect(formatTransferBytes(1536), '1.5 KB');
      expect(formatTransferBytes(2 * 1024 * 1024), '2.0 MB');
    });
  });

  group('tunnel runtime engine (loopback TCP)', () {
    test('local forward (-L) proxies TCP bytes and tracks counters', () async {
      final echo = await _startEchoServer();
      addTearDown(echo.close);

      final transport = _LoopbackForwardTransport();
      var latest = const ForwardRuntimeState();
      final tunnel = ForwardTunnel(
        rule: PortForwardRule(
          id: 'loc1',
          type: ForwardType.local,
          hostId: _sampleHost.id,
          bindHost: '127.0.0.1',
          bindPort: 0,
          targetHost: '127.0.0.1',
          targetPort: echo.port,
        ),
        host: _sampleHost,
        connectTransport: (_, {required isCancelled}) async => transport,
        onStateChanged: (s) => latest = s,
      );
      addTearDown(tunnel.stop);

      await tunnel.start();
      expect(latest.status, ForwardStatus.running);
      expect(latest.boundPort, greaterThan(0));

      final client = await Socket.connect('127.0.0.1', latest.boundPort!);
      client.add(utf8.encode('hello-local-tunnel'));
      final reply = await client.first;
      expect(utf8.decode(reply), 'hello-local-tunnel');
      await client.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(latest.totalConnections, 1);
      expect(latest.bytesUp, greaterThanOrEqualTo(18));
      expect(latest.bytesDown, greaterThanOrEqualTo(18));

      final port = latest.boundPort!;
      await tunnel.stop();
      expect(latest.status, ForwardStatus.stopped);
      expect(transport.closed, isTrue);

      // Port is cleanly released after stop().
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
    });

    test(
      'remote forward (-R) proxies incoming SSH channels to local target',
      () async {
        final localEcho = await _startEchoServer();
        addTearDown(localEcho.close);

        // Pair of connected loopback sockets to feed an incoming channel.
        final peerServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(peerServer.close);
        final incomingFuture = peerServer.first;

        final transport = _LoopbackForwardTransport();
        var latest = const ForwardRuntimeState();
        final tunnel = ForwardTunnel(
          rule: PortForwardRule(
            id: 'rem1',
            type: ForwardType.remote,
            hostId: _sampleHost.id,
            bindHost: '127.0.0.1',
            bindPort: 0,
            targetHost: '127.0.0.1',
            targetPort: localEcho.port,
          ),
          host: _sampleHost,
          connectTransport: (_, {required isCancelled}) async => transport,
          onStateChanged: (s) => latest = s,
        );
        addTearDown(tunnel.stop);

        await tunnel.start();
        expect(latest.status, ForwardStatus.running);
        expect(latest.boundPort, 45123);

        final remoteClient = await Socket.connect('127.0.0.1', peerServer.port);
        final channelSocket = await incomingFuture;
        transport.lastRemote!.controller.add(
          _SocketAsForwardChannel(channelSocket),
        );

        remoteClient.add(utf8.encode('hello-remote-tunnel'));
        final reply = await remoteClient.first;
        expect(utf8.decode(reply), 'hello-remote-tunnel');
        await remoteClient.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(latest.totalConnections, 1);
        expect(latest.bytesUp, greaterThanOrEqualTo(19));
        expect(latest.bytesDown, greaterThanOrEqualTo(19));

        await tunnel.stop();
        expect(transport.lastRemote!.closed, isTrue);
      },
    );

    test('dynamic forward (-D) runs SOCKS5 proxy and counts traffic', () async {
      final echo = await _startEchoServer();
      addTearDown(echo.close);

      final transport = _LoopbackForwardTransport();
      var latest = const ForwardRuntimeState();
      final tunnel = ForwardTunnel(
        rule: PortForwardRule(
          id: 'dyn1',
          type: ForwardType.dynamic,
          hostId: _sampleHost.id,
          bindHost: '127.0.0.1',
          bindPort: 0,
        ),
        host: _sampleHost,
        connectTransport: (_, {required isCancelled}) async => transport,
        onStateChanged: (s) => latest = s,
      );
      addTearDown(tunnel.stop);

      await tunnel.start();
      expect(latest.status, ForwardStatus.running);
      expect(latest.boundPort, greaterThan(0));

      // Perform a real RFC 1928 SOCKS5 CONNECT handshake to 127.0.0.1:echo.port.
      final socks = await Socket.connect('127.0.0.1', latest.boundPort!);
      final received = <int>[];
      final completer = Completer<void>();
      var step = 0;

      socks.listen((chunk) {
        received.addAll(chunk);
        if (step == 0 && received.length >= 2) {
          expect(received.sublist(0, 2), [0x05, 0x00]);
          received.removeRange(0, 2);
          step = 1;
          socks.add([
            0x05, // VER
            0x01, // CONNECT
            0x00, // RSV
            0x01, // IPv4
            127, 0, 0, 1,
            (echo.port >> 8) & 0xFF,
            echo.port & 0xFF,
          ]);
        } else if (step == 1 && received.length >= 10) {
          expect(received[0], 0x05);
          expect(received[1], 0x00); // succeeded
          received.removeRange(0, 10);
          step = 2;
          socks.add(utf8.encode('hello-socks5'));
        } else if (step == 2 && received.length >= 12) {
          if (!completer.isCompleted) completer.complete();
        }
      });

      // Greeting: SOCKS5, 1 method, NO AUTH (0x00).
      socks.add([0x05, 0x01, 0x00]);
      await completer.future.timeout(const Duration(seconds: 5));
      expect(utf8.decode(received), 'hello-socks5');
      await socks.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(latest.totalConnections, 1);
      expect(latest.bytesUp, greaterThanOrEqualTo(12));
      expect(latest.bytesDown, greaterThanOrEqualTo(12));

      await tunnel.stop();
      expect(latest.status, ForwardStatus.stopped);
    });

    test(
      'surfaces errors on port conflict, rejected remote, and transport drop',
      () async {
        // 1. Port already in use.
        final blocker = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(blocker.close);

        var latest = const ForwardRuntimeState();
        final conflict = ForwardTunnel(
          rule: PortForwardRule(
            id: 'err1',
            type: ForwardType.local,
            hostId: _sampleHost.id,
            bindHost: '127.0.0.1',
            bindPort: blocker.port,
            targetHost: '127.0.0.1',
            targetPort: 80,
          ),
          host: _sampleHost,
          connectTransport: (_, {required isCancelled}) async =>
              _LoopbackForwardTransport(),
          onStateChanged: (s) => latest = s,
        );
        await conflict.start();
        expect(latest.status, ForwardStatus.error);
        expect(latest.error, isNotNull);

        // 2. Remote forward rejected by server.
        final rejected = ForwardTunnel(
          rule: const PortForwardRule(
            id: 'err2',
            type: ForwardType.remote,
            hostId: 'h1',
            bindHost: '127.0.0.1',
            bindPort: 9090,
            targetHost: '127.0.0.1',
            targetPort: 3000,
          ),
          host: _sampleHost,
          connectTransport: (_, {required isCancelled}) async =>
              _LoopbackForwardTransport(rejectRemote: true),
          onStateChanged: (s) => latest = s,
        );
        await rejected.start();
        expect(latest.status, ForwardStatus.error);
        expect(latest.error, contains('9090'));

        // 3. Unexpected SSH transport drop marks tunnel as error.
        final dropTransport = _LoopbackForwardTransport();
        final dropping = ForwardTunnel(
          rule: const PortForwardRule(
            id: 'err3',
            type: ForwardType.local,
            hostId: 'h1',
            bindHost: '127.0.0.1',
            bindPort: 0,
            targetHost: '127.0.0.1',
            targetPort: 80,
          ),
          host: _sampleHost,
          connectTransport: (_, {required isCancelled}) async => dropTransport,
          onStateChanged: (s) => latest = s,
        );
        await dropping.start();
        expect(latest.status, ForwardStatus.running);
        dropTransport.simulateDrop();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(latest.status, ForwardStatus.error);
      },
    );
  });

  group('forwarding UI', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    testWidgets('create, start/stop with badge, filter, and delete rules', (
      tester,
    ) async {
      // Seed one saved host so the editor can target it.
      final hostRepo = HostRepository(
        dataDir: env.dataDir,
        secrets: env.secrets,
      );
      await tester.runAsync(
        () => hostRepo.save(const HostsData(hosts: [_sampleHost])),
      );

      // Reserve an ephemeral free port, then release it for the UI rule.
      final probe = (await tester.runAsync(
        () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      ))!;
      final freePort = probe.port;
      await tester.runAsync(probe.close);

      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            forwardTransportConnectorProvider.overrideWithValue(
              (_, {required isCancelled}) async => _LoopbackForwardTransport(),
            ),
          ],
          child: const UesshApp(),
        ),
      );
      await settleIo(tester);

      // Open Forwarding page.
      await tester.tap(find.text('转发'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('还没有转发规则'), findsOneWidget);

      // Create a Local (-L) rule.
      await tester.tap(find.byKey(const ValueKey('new-forward-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('forward-name-field')),
        '生产数据库',
      );
      await tester.enterText(
        find.byKey(const ValueKey('forward-bind-port-field')),
        '$freePort',
      );
      await tester.enterText(
        find.byKey(const ValueKey('forward-target-port-field')),
        '3306',
      );
      await tester.pump();
      expect(
        find.textContaining('-L 127.0.0.1:$freePort:127.0.0.1:3306'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('save-forward')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('生产数据库'), findsOneWidget);
      expect(find.text('127.0.0.1:$freePort'), findsOneWidget);

      // Create a Dynamic SOCKS5 (-D) rule: target fields hide automatically.
      await tester.tap(find.byKey(const ValueKey('new-forward-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('forward-type-selector')),
          matching: find.text('动态 (-D)'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('forward-target-port-field')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('forward-name-field')),
        '公司代理',
      );
      await tester.tap(find.byKey(const ValueKey('save-forward')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('公司代理'), findsOneWidget);
      expect(find.text('socks5://127.0.0.1:1080'), findsOneWidget);

      // Start the Local rule and verify live status + sidebar active badge + Stop all.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(UesshApp)),
      );
      final rules = container.read(portForwardsProvider).value!;
      final dbRule = rules.firstWhere((r) => r.name == '生产数据库');

      await tester.tap(find.byKey(ValueKey('forward-toggle-${dbRule.id}')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('1 个运行中'), findsOneWidget);
      expect(find.byKey(const ValueKey('forward-stop-all')), findsOneWidget);
      expect(
        find.byKey(ValueKey('forward-traffic-${dbRule.id}')),
        findsOneWidget,
      );

      // Stop all shuts down the active tunnel.
      await tester.tap(find.byKey(const ValueKey('forward-stop-all')));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('forward-stop-all')), findsNothing);

      // Filter by Dynamic (-D).
      await tester.tap(find.widgetWithText(FilterChip, '动态 (-D)'));
      await tester.pumpAndSettle();
      expect(find.text('公司代理'), findsOneWidget);
      expect(find.text('生产数据库'), findsNothing);

      // Reset to All and delete '公司代理'.
      await tester.tap(find.widgetWithText(FilterChip, '全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('公司代理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-forward')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('公司代理'), findsNothing);
      expect(find.text('生产数据库'), findsOneWidget);
    });
  });
}
