import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../core/app_log.dart';
import '../../l10n/l10n.dart';
import '../hosts/host.dart';
import '../hosts/host_repository.dart';
import '../keys/ssh_key.dart';
import '../terminal/known_hosts.dart';
import '../terminal/terminal_session.dart';
import 'port_forward.dart';

enum ForwardStatus { stopped, starting, running, error }

/// Live runtime status and traffic counters for a single [PortForwardRule].
class ForwardRuntimeState {
  const ForwardRuntimeState({
    this.status = ForwardStatus.stopped,
    this.error,
    this.boundPort,
    this.activeConnections = 0,
    this.totalConnections = 0,
    this.bytesUp = 0,
    this.bytesDown = 0,
    this.startedAt,
  });

  final ForwardStatus status;
  final String? error;

  /// Actual bound port once listening (equals the rule's `bindPort`, or the
  /// OS/server assigned port when `bindPort == 0`).
  final int? boundPort;
  final int activeConnections;
  final int totalConnections;
  final int bytesUp;
  final int bytesDown;
  final DateTime? startedAt;

  bool get isRunning => status == ForwardStatus.running;
  bool get isStarting => status == ForwardStatus.starting;
  bool get isActive => isRunning || isStarting;

  ForwardRuntimeState copyWith({
    ForwardStatus? status,
    Object? error = _keep,
    Object? boundPort = _keep,
    int? activeConnections,
    int? totalConnections,
    int? bytesUp,
    int? bytesDown,
    Object? startedAt = _keep,
  }) => ForwardRuntimeState(
    status: status ?? this.status,
    error: identical(error, _keep) ? this.error : error as String?,
    boundPort: identical(boundPort, _keep) ? this.boundPort : boundPort as int?,
    activeConnections: activeConnections ?? this.activeConnections,
    totalConnections: totalConnections ?? this.totalConnections,
    bytesUp: bytesUp ?? this.bytesUp,
    bytesDown: bytesDown ?? this.bytesDown,
    startedAt: identical(startedAt, _keep)
        ? this.startedAt
        : startedAt as DateTime?,
  );

  static const _keep = Object();
}

/// Formats byte counts cleanly (`0 B`, `1.2 KB`, `3.4 MB`, `1.1 GB`).
String formatTransferBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Abstraction over `SSHRemoteForward` so tests can drive remote forwarding
/// over local sockets without a real SSH server.
abstract class RemoteForwardHandle {
  String get host;
  int get port;
  Stream<SSHForwardChannel> get connections;
  Future<void> close();
}

/// Abstraction over an authenticated `SSHClient` used by [ForwardTunnel].
abstract class ForwardTransport {
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  });

  Future<RemoteForwardHandle?> forwardRemote({String? host, int? port});

  Future<void> get done;

  void close();
}

/// Factory that connects a [ForwardTransport] for a given [Host].
typedef ForwardTransportConnector = Future<ForwardTransport> Function(
  Host host, {
  required bool Function() isCancelled,
});

class _SshRemoteForwardHandle implements RemoteForwardHandle {
  _SshRemoteForwardHandle(this._forward);

  final SSHRemoteForward _forward;

  @override
  String get host => _forward.host;

  @override
  int get port => _forward.port;

  @override
  Stream<SSHForwardChannel> get connections => _forward.connections;

  @override
  Future<void> close() async {
    _forward.close();
  }
}

/// Production [ForwardTransport] backed by an authenticated `dartssh2`
/// [SSHClient].
class SshForwardTransport implements ForwardTransport {
  SshForwardTransport(this._client);

  final SSHClient _client;

  static Future<SshForwardTransport> connect({
    required Host host,
    required HostRepository repository,
    required KnownHostsStore knownHosts,
    required SessionPrompts prompts,
    KeyRepository? keys,
    required bool Function() isCancelled,
  }) async {
    final client = await openAuthenticatedSshClient(
      host: host,
      repository: repository,
      knownHosts: knownHosts,
      prompts: prompts,
      keys: keys,
      isCancelled: isCancelled,
    );
    return SshForwardTransport(client);
  }

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) => _client.forwardLocal(
    remoteHost,
    remotePort,
    localHost: localHost,
    localPort: localPort,
  );

  @override
  Future<RemoteForwardHandle?> forwardRemote({String? host, int? port}) async {
    final rf = await _client.forwardRemote(host: host, port: port);
    return rf == null ? null : _SshRemoteForwardHandle(rf);
  }

  @override
  Future<void> get done => _client.done;

  @override
  void close() => _client.close();
}

/// Runs a single port-forwarding tunnel (local, remote, or dynamic SOCKS5),
/// pumping TCP bytes across the SSH transport and reporting live traffic stats.
class ForwardTunnel {
  ForwardTunnel({
    required this.rule,
    required this.host,
    required this.connectTransport,
    required this.onStateChanged,
  });

  final PortForwardRule rule;
  final Host host;
  final ForwardTransportConnector connectTransport;
  final void Function(ForwardRuntimeState state) onStateChanged;

  ForwardRuntimeState _state = const ForwardRuntimeState();
  ForwardRuntimeState get state => _state;

  ForwardTransport? _transport;
  ServerSocket? _localServer;
  StreamSubscription<Socket>? _localSub;
  RemoteForwardHandle? _remoteForward;
  StreamSubscription<SSHForwardChannel>? _remoteSub;
  SSHDynamicForward? _dynamicForward;
  final _bridges = <_SocketChannelBridge>{};

  int _generation = 0;
  bool _stoppedByUser = false;
  Timer? _statsThrottle;

  /// Starts the SSH transport and binds the forwarding listener.
  Future<void> start() async {
    final gen = ++_generation;
    _stoppedByUser = false;
    _emit(const ForwardRuntimeState(status: ForwardStatus.starting));
    log.info(
      'forward',
      'Starting ${rule.type.name} forward "${rule.displayName}" via ${host.target}',
    );

    try {
      final transport = await connectTransport(
        host,
        isCancelled: () => gen != _generation,
      );
      if (gen != _generation) {
        transport.close();
        return;
      }
      _transport = transport;
      // Swallow unhandled errors on transport.done; handled via _onTransportDrop.
      unawaited(
        transport.done.then(
          (_) => _onTransportDropped(gen),
          onError: (Object _) => _onTransportDropped(gen),
        ),
      );

      final int boundPort;
      switch (rule.type) {
        case ForwardType.local:
          boundPort = await _startLocal(transport, gen);
        case ForwardType.remote:
          boundPort = await _startRemote(transport, gen);
        case ForwardType.dynamic:
          boundPort = await _startDynamic(transport, gen);
      }

      if (gen != _generation) {
        await _teardown();
        return;
      }

      _emit(
        _state.copyWith(
          status: ForwardStatus.running,
          error: null,
          boundPort: boundPort,
          startedAt: DateTime.now(),
        ),
      );
      log.info(
        'forward',
        'Started ${rule.type.name} forward "${rule.displayName}" on port $boundPort',
      );
    } on _ForwardException catch (e) {
      if (gen != _generation) return;
      await _teardown();
      log.warn('forward', 'Forward "${rule.displayName}" failed: ${e.message}');
      _emit(ForwardRuntimeState(status: ForwardStatus.error, error: e.message));
    } catch (e) {
      if (gen != _generation) return;
      await _teardown();
      final msg = describeConnectError(e, host);
      log.warn('forward', 'Forward "${rule.displayName}" failed: $e');
      _emit(ForwardRuntimeState(status: ForwardStatus.error, error: msg));
    }
  }

  /// Stops the tunnel, closes all active proxied connections, and releases
  /// bound ports and the SSH transport.
  Future<void> stop() async {
    _stoppedByUser = true;
    _generation++;
    await _teardown();
    _emit(const ForwardRuntimeState(status: ForwardStatus.stopped));
    log.info('forward', 'Stopped forward "${rule.displayName}"');
  }

  Future<int> _startLocal(ForwardTransport transport, int gen) async {
    final bindHost = rule.effectiveBindHost;
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(bindHost, rule.bindPort);
    } on SocketException catch (e) {
      final reason = e.osError?.message ?? e.message;
      throw _ForwardException(
        currentL10n.forwardBindFailed('$bindHost:${rule.bindPort}', reason),
      );
    }
    if (gen != _generation) {
      await server.close();
      return 0;
    }
    _localServer = server;
    _localSub = server.listen(
      (socket) => unawaited(_handleLocalClient(transport, socket, gen)),
      onError: (Object e) {
        log.warn('forward', 'Local listener error (${rule.displayName}): $e');
      },
    );
    return server.port;
  }

  Future<void> _handleLocalClient(
    ForwardTransport transport,
    Socket client,
    int gen,
  ) async {
    if (gen != _generation) {
      client.destroy();
      return;
    }
    _onConnOpened();
    try {
      final channel = await transport.forwardLocal(
        rule.effectiveTargetHost,
        rule.targetPort,
        localHost: client.remoteAddress.address,
        localPort: client.remotePort,
      );
      if (gen != _generation) {
        channel.destroy();
        client.destroy();
        _onConnClosed();
        return;
      }
      _attachBridge(
        client,
        channel,
        onSocketToChannel: _addBytesUp,
        onChannelToSocket: _addBytesDown,
      );
    } catch (e) {
      log.warn(
        'forward',
        'Local forward dial failed (${rule.effectiveTargetHost}:${rule.targetPort}): $e',
      );
      client.destroy();
      _onConnClosed();
    }
  }

  Future<int> _startRemote(ForwardTransport transport, int gen) async {
    final bindHost = rule.bindHost.trim();
    final rf = await transport.forwardRemote(
      host: bindHost.isEmpty ? null : bindHost,
      port: rule.bindPort,
    );
    if (rf == null) {
      throw _ForwardException(
        currentL10n.forwardRemoteRejected(
          '${rule.effectiveBindHost}:${rule.bindPort}',
        ),
      );
    }
    if (gen != _generation) {
      await rf.close();
      return 0;
    }
    _remoteForward = rf;
    _remoteSub = rf.connections.listen(
      (channel) => unawaited(_handleRemoteClient(channel, gen)),
      onError: (Object e) {
        log.warn('forward', 'Remote listener error (${rule.displayName}): $e');
      },
    );
    return rf.port;
  }

  Future<void> _handleRemoteClient(SSHForwardChannel channel, int gen) async {
    if (gen != _generation) {
      channel.destroy();
      return;
    }
    _onConnOpened();
    try {
      final localSocket = await Socket.connect(
        rule.effectiveTargetHost,
        rule.targetPort,
        timeout: const Duration(seconds: 10),
      );
      if (gen != _generation) {
        localSocket.destroy();
        channel.destroy();
        _onConnClosed();
        return;
      }
      _attachBridge(
        localSocket,
        channel,
        onSocketToChannel: _addBytesUp,
        onChannelToSocket: _addBytesDown,
      );
    } catch (e) {
      log.warn(
        'forward',
        'Remote forward local connect failed (${rule.effectiveTargetHost}:${rule.targetPort}): $e',
      );
      channel.destroy();
      _onConnClosed();
    }
  }

  Future<int> _startDynamic(ForwardTransport transport, int gen) async {
    final bindHost = rule.effectiveBindHost;
    final SSHDynamicForward dyn;
    try {
      dyn = await startDynamicForward(
        bindHost: bindHost,
        bindPort: rule.bindPort,
        options: const SSHDynamicForwardOptions(),
        dial: (targetHost, targetPort) async {
          final channel = await transport.forwardLocal(targetHost, targetPort);
          return _MeteredForwardChannel(
            channel,
            onOpen: _onConnOpened,
            onBytesUp: _addBytesUp,
            onBytesDown: _addBytesDown,
            onClose: _onConnClosed,
          );
        },
      );
    } on SocketException catch (e) {
      final reason = e.osError?.message ?? e.message;
      throw _ForwardException(
        currentL10n.forwardBindFailed('$bindHost:${rule.bindPort}', reason),
      );
    }
    if (gen != _generation) {
      await dyn.close();
      return 0;
    }
    _dynamicForward = dyn;
    return dyn.port;
  }

  void _attachBridge(
    Socket socket,
    SSHForwardChannel channel, {
    required void Function(int bytes) onSocketToChannel,
    required void Function(int bytes) onChannelToSocket,
  }) {
    late final _SocketChannelBridge bridge;
    bridge = _SocketChannelBridge(
      socket: socket,
      channel: channel,
      onSocketToChannel: onSocketToChannel,
      onChannelToSocket: onChannelToSocket,
      onClosed: () {
        _bridges.remove(bridge);
        _onConnClosed();
      },
    );
    _bridges.add(bridge);
    bridge.start();
  }

  void _onTransportDropped(int gen) {
    if (gen != _generation || _stoppedByUser) return;
    if (_state.status != ForwardStatus.running) return;
    _generation++;
    log.warn('forward', 'Tunnel "${rule.displayName}" connection lost');
    unawaited(_teardown());
    _emit(
      _state.copyWith(
        status: ForwardStatus.error,
        error: currentL10n.forwardConnectionLost,
        activeConnections: 0,
      ),
    );
  }

  void _onConnOpened() {
    _state = _state.copyWith(
      activeConnections: _state.activeConnections + 1,
      totalConnections: _state.totalConnections + 1,
    );
    _emitNow();
  }

  void _onConnClosed() {
    final next = _state.activeConnections > 0
        ? _state.activeConnections - 1
        : 0;
    _state = _state.copyWith(activeConnections: next);
    _emitNow();
  }

  void _addBytesUp(int count) {
    if (count <= 0) return;
    _state = _state.copyWith(bytesUp: _state.bytesUp + count);
    _scheduleStatsEmit();
  }

  void _addBytesDown(int count) {
    if (count <= 0) return;
    _state = _state.copyWith(bytesDown: _state.bytesDown + count);
    _scheduleStatsEmit();
  }

  void _scheduleStatsEmit() {
    if (_statsThrottle?.isActive ?? false) return;
    _statsThrottle = Timer(const Duration(milliseconds: 200), _emitNow);
  }

  void _emit(ForwardRuntimeState next) {
    _state = next;
    _emitNow();
  }

  void _emitNow() {
    _statsThrottle?.cancel();
    _statsThrottle = null;
    onStateChanged(_state);
  }

  Future<void> _teardown() async {
    _statsThrottle?.cancel();
    _statsThrottle = null;

    final localSub = _localSub;
    _localSub = null;
    await localSub?.cancel();

    final localServer = _localServer;
    _localServer = null;
    try {
      await localServer?.close();
    } catch (_) {}

    final remoteSub = _remoteSub;
    _remoteSub = null;
    await remoteSub?.cancel();

    final remoteForward = _remoteForward;
    _remoteForward = null;
    try {
      await remoteForward?.close();
    } catch (_) {}

    final dyn = _dynamicForward;
    _dynamicForward = null;
    try {
      await dyn?.close();
    } catch (_) {}

    for (final b in _bridges.toList()) {
      b.close();
    }
    _bridges.clear();

    final transport = _transport;
    _transport = null;
    try {
      transport?.close();
    } catch (_) {}
  }
}

class _ForwardException implements Exception {
  const _ForwardException(this.message);
  final String message;
}

/// Bidirectionally proxies bytes between a TCP [Socket] and an
/// [SSHForwardChannel], preserving half-close semantics and swallowing abrupt
/// peer reset errors cleanly.
class _SocketChannelBridge {
  _SocketChannelBridge({
    required this.socket,
    required this.channel,
    required this.onSocketToChannel,
    required this.onChannelToSocket,
    required this.onClosed,
  });

  final Socket socket;
  final SSHForwardChannel channel;
  final void Function(int bytes) onSocketToChannel;
  final void Function(int bytes) onChannelToSocket;
  final void Function() onClosed;

  StreamSubscription<Uint8List>? _socketSub;
  StreamSubscription<Uint8List>? _channelSub;
  bool _socketDone = false;
  bool _channelDone = false;
  bool _closed = false;

  void start() {
    unawaited(socket.done.catchError((Object _) {}));
    unawaited(channel.done.catchError((Object _) {}));

    _socketSub = socket.listen(
      (chunk) {
        if (_closed) return;
        onSocketToChannel(chunk.length);
        try {
          channel.sink.add(chunk);
        } catch (_) {
          _cleanup(destroy: true);
        }
      },
      onDone: () {
        _socketDone = true;
        try {
          unawaited(channel.sink.close().catchError((Object _) {}));
        } catch (_) {}
        if (_channelDone) _cleanup();
      },
      onError: (Object _) => _cleanup(destroy: true),
      cancelOnError: true,
    );

    _channelSub = channel.stream.listen(
      (chunk) {
        if (_closed) return;
        onChannelToSocket(chunk.length);
        try {
          socket.add(chunk);
        } catch (_) {
          _cleanup(destroy: true);
        }
      },
      onDone: () {
        _channelDone = true;
        try {
          unawaited(socket.close().catchError((Object _) {}));
        } catch (_) {}
        if (_socketDone) _cleanup();
      },
      onError: (Object _) => _cleanup(destroy: true),
      cancelOnError: true,
    );
  }

  void close() => _cleanup(destroy: true);

  void _cleanup({bool destroy = false}) {
    if (_closed) return;
    _closed = true;
    unawaited(_socketSub?.cancel());
    unawaited(_channelSub?.cancel());
    if (destroy) {
      try {
        socket.destroy();
      } catch (_) {}
      try {
        channel.destroy();
      } catch (_) {}
    } else {
      try {
        unawaited(socket.close().catchError((Object _) {}));
      } catch (_) {}
      try {
        unawaited(channel.close().catchError((Object _) {}));
      } catch (_) {}
    }
    onClosed();
  }
}

/// Wraps an [SSHForwardChannel] to count bytes and connection lifecycle for
/// `dartssh2`'s built-in SOCKS5 dynamic forwarder.
class _MeteredForwardChannel implements SSHForwardChannel {
  _MeteredForwardChannel(
    this._inner, {
    required void Function() onOpen,
    required void Function(int bytes) onBytesUp,
    required void Function(int bytes) onBytesDown,
    required this.onClose,
  }) : _sink = _MeteredSink(_inner.sink, onBytesUp) {
    onOpen();
    _stream = _inner.stream.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          onBytesDown(chunk.length);
          sink.add(chunk);
        },
        handleDone: (sink) {
          _markClosed();
          sink.close();
        },
        handleError: (error, st, sink) {
          _markClosed();
          sink.addError(error, st);
        },
      ),
    );
    unawaited(
      _inner.done.then((_) => _markClosed(), onError: (_) => _markClosed()),
    );
  }

  final SSHForwardChannel _inner;
  final void Function() onClose;
  final _MeteredSink _sink;
  late final Stream<Uint8List> _stream;
  bool _closed = false;

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    onClose();
  }

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _sink;

  @override
  Future<void> close() {
    _markClosed();
    return _inner.close();
  }

  @override
  void destroy() {
    _markClosed();
    _inner.destroy();
  }

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();
}

class _MeteredSink implements StreamSink<List<int>> {
  _MeteredSink(this._inner, this._onBytes);

  final StreamSink<List<int>> _inner;
  final void Function(int bytes) _onBytes;

  @override
  void add(List<int> event) {
    _onBytes(event.length);
    _inner.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(
    stream.map((chunk) {
      _onBytes(chunk.length);
      return chunk;
    }),
  );

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;
}
