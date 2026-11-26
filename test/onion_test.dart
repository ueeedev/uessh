import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/hosts/hosts_providers.dart';
import 'package:uessh/features/onion/onion_providers.dart';
import 'package:uessh/features/onion/onion_route.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

const _hostA = Host(
  id: 'h-a',
  label: '服务器 A',
  address: '10.0.0.1',
  port: 22,
  username: 'ops',
  authMethod: AuthMethod.password,
);

const _hostB = Host(
  id: 'h-b',
  label: '服务器 B',
  address: '10.0.0.2',
  port: 2222,
  username: 'ops',
  authMethod: AuthMethod.password,
);

const _hostC = Host(
  id: 'h-c',
  label: '服务器 C',
  address: '10.0.0.3',
  port: 22,
  username: 'ops',
  authMethod: AuthMethod.password,
);

class _DummySocket implements SSHSocket {
  _DummySocket(this.tag);

  final String tag;
  bool destroyed = false;
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => const Stream.empty();

  @override
  StreamSink<List<int>> get sink => StreamController<List<int>>().sink;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() {
    destroyed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}
}

class _FakeOnionSession extends TerminalSession {
  _FakeOnionSession({
    required super.host,
    required super.jumpHosts,
    super.chainLabel,
    required super.repository,
    required super.knownHosts,
    required super.prompts,
  });

  @override
  Future<void> connect({bool auto = false}) async {
    status = SessionStatus.connected;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    status = SessionStatus.closed;
    notifyListeners();
  }
}

void main() {
  group('OnionRoute model & repository', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    test('persists onion routes and builds summary & ssh -J command', () async {
      final repo = OnionRouteRepository(dataDir: env.dataDir);
      final route = OnionRoute(
        id: 'r1',
        name: '核心链路',
        jumpHostIds: const ['h-a', 'h-b'],
        targetHostId: 'h-c',
        note: '通过 A、B 跳转到 C',
        createdAt: DateTime.utc(2026, 11, 25),
      );
      await repo.save([route]);

      final loaded = await repo.load();
      expect(loaded, hasLength(1));
      final r = loaded.single;
      expect(r.id, 'r1');
      expect(r.name, '核心链路');
      expect(r.jumpHostIds, ['h-a', 'h-b']);
      expect(r.targetHostId, 'h-c');
      expect(r.allHostIds, ['h-a', 'h-b', 'h-c']);
      expect(r.hopCount, 3);
      expect(r.note, '通过 A、B 跳转到 C');

      final byId = {'h-a': _hostA, 'h-b': _hostB, 'h-c': _hostC};
      final resolved = r.resolve(byId);
      expect(resolved, isNotNull);
      expect(resolved!.jumps.map((h) => h.id), ['h-a', 'h-b']);
      expect(resolved.target.id, 'h-c');
      expect(r.displayTitle(byId), '核心链路');
      expect(r.routeSummary(byId), '服务器 A → 服务器 B → 服务器 C');
      expect(
        r.sshCommandPreview(byId),
        'ssh -J ops@10.0.0.1,ops@10.0.0.2:2222 ops@10.0.0.3',
      );

      // Unnamed route falls back to A → B → C
      final unnamed = r.copyWith(name: '');
      expect(unnamed.displayTitle(byId), '服务器 A → 服务器 B → 服务器 C');

      // Missing hop invalidates resolve()
      expect(r.resolve({'h-a': _hostA, 'h-c': _hostC}), isNull);
      expect(r.copyWith(jumpHostIds: const []).resolve(byId), isNull);
    });
  });

  group('establishOnionChain', () {
    test('connects A -> B -> C in order forwarding each hop through previous client', () async {
      final events = <String>[];
      final sockets = <String, _DummySocket>{};

      final result = await establishOnionChain<String>(
        chain: const [_hostA, _hostB, _hostC],
        onHopConnecting: (step, total, hop) =>
            events.add('connecting:$step/$total:${hop.id}'),
        onHopForwarding: (step, total, from, to) =>
            events.add('forwarding:$step/$total:${from.id}->${to.id}'),
        connectHop: (hop, forwardedSocket, isTarget) async {
          final sockTag = (forwardedSocket as _DummySocket?)?.tag ?? 'direct';
          events.add('connect:${hop.id}:via=$sockTag:target=$isTarget');
          return 'client-${hop.id}';
        },
        forwardNext: (prevClient, from, to) async {
          final tag = '$prevClient->${to.id}';
          final sock = _DummySocket(tag);
          sockets[tag] = sock;
          return sock;
        },
        closeClient: (c) => events.add('close:$c'),
      );

      expect(result.client, 'client-h-c');
      expect(result.jumpClients, ['client-h-a', 'client-h-b']);
      expect(events, [
        'connecting:1/3:h-a',
        'connect:h-a:via=direct:target=false',
        'forwarding:1/3:h-a->h-b',
        'connecting:2/3:h-b',
        'connect:h-b:via=client-h-a->h-b:target=false',
        'forwarding:2/3:h-b->h-c',
        'connecting:3/3:h-c',
        'connect:h-c:via=client-h-b->h-c:target=true',
      ]);
    });

    test('closes opened intermediate clients in reverse order when final hop fails', () async {
      final closed = <String>[];
      await expectLater(
        establishOnionChain<String>(
          chain: const [_hostA, _hostB, _hostC],
          connectHop: (hop, _, _) async {
            if (hop.id == 'h-c') throw StateError('C refused');
            return 'client-${hop.id}';
          },
          forwardNext: (prev, _, to) async => _DummySocket('$prev->${to.id}'),
          closeClient: closed.add,
        ),
        throwsA(isA<StateError>()),
      );
      expect(closed, ['client-h-b', 'client-h-a']);
    });

    test(
      'cancelling mid-chain tears down opened hops and forwarded socket',
      () async {
        final closed = <String>[];
        var cancelled = false;
        _DummySocket? forwarded;

        await expectLater(
          establishOnionChain<String>(
            chain: const [_hostA, _hostB, _hostC],
            isCancelled: () => cancelled,
            connectHop: (hop, _, _) async => 'client-${hop.id}',
            forwardNext: (prev, _, to) async {
              cancelled = true;
              forwarded = _DummySocket('$prev->${to.id}');
              return forwarded!;
            },
            closeClient: closed.add,
          ),
          throwsA(anything),
        );
        expect(closed, ['client-h-a']);
        expect(forwarded?.destroyed, isTrue);
      },
    );
  });

  group('OnionPage UI & Host Card Picker', () {
    late TestEnv env;

    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    testWidgets(
      'creates onion card by picking saved host cards, connects, and deletes',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final hostRepo = HostRepository(
          dataDir: env.dataDir,
          secrets: env.secrets,
        );
        await tester.runAsync(
          () => hostRepo.save(const HostsData(hosts: [_hostA, _hostB, _hostC])),
        );

        final opened =
            <({List<Host> jumps, Host target, String? chainLabel})>[];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...env.overrides,
              onionSessionFactoryProvider.overrideWith(
                (ref) =>
                    ({
                      required Host targetHost,
                      required List<Host> jumpHosts,
                      String? chainLabel,
                    }) {
                      opened.add((
                        jumps: jumpHosts,
                        target: targetHost,
                        chainLabel: chainLabel,
                      ));
                      return _FakeOnionSession(
                        host: targetHost,
                        jumpHosts: jumpHosts,
                        chainLabel: chainLabel,
                        repository: ref.read(hostRepositoryProvider),
                        knownHosts: ref.read(knownHostsProvider),
                        prompts: FakePrompts(),
                      );
                    },
              ),
            ],
            child: const UesshApp(),
          ),
        );
        await settleIo(tester);

        // Navigate to 洋葱连接 in the left sidebar.
        await tester.tap(find.text('洋葱连接'));
        await settleIo(tester);
        expect(find.text('还没有洋葱连接'), findsOneWidget);

        // Open new onion route editor.
        await tester.tap(find.byKey(const ValueKey('new-onion-button')));
        await tester.pumpAndSettle();

        // Saving without nodes shows inline validation errors.
        await tester.tap(find.byKey(const ValueKey('save-onion')));
        await tester.pumpAndSettle();
        expect(find.text('请至少新增一个中间节点'), findsOneWidget);
        expect(find.text('请选择结束节点'), findsOneWidget);

        // Add intermediate node 1 from Host Card Picker -> pick 服务器 A.
        await tester.tap(find.byKey(const ValueKey('onion-add-jump')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('onion-host-card-picker')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('onion-pick-host-h-a')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('onion-pick-host-h-b')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('onion-pick-host-h-c')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('onion-pick-host-h-a')));
        await tester.pumpAndSettle();

        // Add intermediate node 2 -> verify 服务器 A is marked 已在链路中 -> pick 服务器 B.
        await tester.tap(find.byKey(const ValueKey('onion-add-jump')));
        await tester.pumpAndSettle();
        expect(find.text('已在链路中'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('onion-pick-host-h-b')));
        await tester.pumpAndSettle();

        // Select destination node -> pick 服务器 C.
        await tester.ensureVisible(
          find.byKey(const ValueKey('onion-select-target')),
        );
        await tester.tap(find.byKey(const ValueKey('onion-select-target')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('onion-pick-host-h-c')));
        await tester.pumpAndSettle();

        // Verify visibility hint and ssh -J CLI preview.
        expect(find.text('目标节点「服务器 C」仅可见来自「服务器 B」的 SSH 连接'), findsOneWidget);
        expect(
          find.textContaining(
            'ssh -J ops@10.0.0.1,ops@10.0.0.2:2222 ops@10.0.0.3',
          ),
          findsOneWidget,
        );

        // Reorder jump nodes: move node 1 (B) up so chain becomes B -> A -> C,
        // then move it back down to A -> B -> C.
        await tester.tap(find.byKey(const ValueKey('onion-jump-up-1')));
        await tester.pumpAndSettle();
        expect(find.text('目标节点「服务器 C」仅可见来自「服务器 A」的 SSH 连接'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('onion-jump-down-0')));
        await tester.pumpAndSettle();
        expect(find.text('目标节点「服务器 C」仅可见来自「服务器 B」的 SSH 连接'), findsOneWidget);

        // Fill name and note, then save.
        await tester.enterText(
          find.byKey(const ValueKey('onion-name-field')),
          '核心跳板链路',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('onion-note-field')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('onion-note-field')),
          '通过 A、B 到达 C',
        );
        await tester.tap(find.byKey(const ValueKey('save-onion')));
        await settleIo(tester);

        // Verify card is displayed on OnionPage.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(UesshApp)),
        );
        final savedRoutes = container.read(onionRoutesProvider).value!;
        expect(savedRoutes, hasLength(1));
        final routeId = savedRoutes.single.id;

        expect(find.byKey(ValueKey('onion-card-$routeId')), findsOneWidget);
        expect(find.text('核心跳板链路'), findsOneWidget);
        expect(find.text('3 跳'), findsOneWidget);
        expect(find.text('服务器 A'), findsOneWidget);
        expect(find.text('服务器 B'), findsOneWidget);
        expect(find.text('服务器 C'), findsOneWidget);

        // Open the connection card -> launches multi-hop terminal session!
        await tester.tap(find.byKey(ValueKey('onion-connect-$routeId')));
        await settleIo(tester);

        expect(opened, hasLength(1));
        expect(opened.single.jumps.map((h) => h.id), ['h-a', 'h-b']);
        expect(opened.single.target.id, 'h-c');
        expect(opened.single.chainLabel, '核心跳板链路');
        expect(find.byKey(const ValueKey('tab-onion-icon')), findsOneWidget);

        // Switch back to workbench and delete the card.
        await tester.tap(find.byKey(const ValueKey('home-tab')));
        await settleIo(tester);
        await tester.tap(find.byKey(ValueKey('onion-edit-$routeId')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('delete-onion')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '删除'));
        await settleIo(tester);

        expect(find.text('还没有洋葱连接'), findsOneWidget);
      },
    );
  });
}
