import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'app_log.dart';
import 'proxy_settings.dart';
import 'system_proxy.dart';

/// Raised when establishing a tunnel through an HTTP or SOCKS5 proxy fails.
class ProxyConnectException implements Exception {
  const ProxyConnectException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// An established raw TCP tunnel through a proxy, carrying any trailing bytes
/// that arrived in the same packet as the proxy's handshake response.
class ProxiedSshSocket implements SSHSocket {
  ProxiedSshSocket._(this._socket, this._stream, this._closeSub);

  final Socket _socket;
  final Stream<Uint8List> _stream;
  final Future<void> Function() _closeSub;

  @override
  Stream<Uint8List> get stream => _stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() async {
    await _closeSub();
    await _socket.close();
  }

  @override
  void destroy() {
    unawaited(_closeSub());
    _socket.destroy();
  }

  @override
  Future<void> flush() => _socket.flush();
}

/// Connects an [SSHSocket] to [targetHost]:[targetPort], routing through
/// [proxy] when configured (`direct`, `system`, or `custom` HTTP/SOCKS5).
Future<SSHSocket> connectSshSocketWithProxy({
  required String targetHost,
  required int targetPort,
  required ProxySettings proxy,
  String? password,
  Duration timeout = const Duration(seconds: 10),
  SystemProxyResolver? systemResolver,
}) async {
  switch (proxy.mode) {
    case ProxyMode.direct:
      return SSHSocket.connect(targetHost, targetPort, timeout: timeout);
    case ProxyMode.system:
      final resolver = systemResolver ?? _sharedSystemResolver;
      final endpoint = resolver.resolveForTcp(targetHost);
      if (endpoint == null) {
        return SSHSocket.connect(targetHost, targetPort, timeout: timeout);
      }
      log.info(
        'ssh',
        'Connecting to $targetHost:$targetPort via system '
            '${endpoint.isSocks5 ? 'socks5' : 'http'} proxy '
            '${endpoint.host}:${endpoint.port}',
      );
      return endpoint.isSocks5
          ? connectSshViaSocks5(
              proxyHost: endpoint.host,
              proxyPort: endpoint.port,
              targetHost: targetHost,
              targetPort: targetPort,
              timeout: timeout,
            )
          : connectSshViaHttpConnect(
              proxyHost: endpoint.host,
              proxyPort: endpoint.port,
              targetHost: targetHost,
              targetPort: targetPort,
              timeout: timeout,
            );
    case ProxyMode.custom:
      if (!proxy.isCustomValid) {
        return SSHSocket.connect(targetHost, targetPort, timeout: timeout);
      }
      log.info(
        'ssh',
        'Connecting to $targetHost:$targetPort via custom ${proxy.displayEndpoint}',
      );
      return proxy.scheme == ProxyScheme.socks5
          ? connectSshViaSocks5(
              proxyHost: proxy.host.trim(),
              proxyPort: proxy.port,
              targetHost: targetHost,
              targetPort: targetPort,
              username: proxy.username.trim(),
              password: password,
              timeout: timeout,
            )
          : connectSshViaHttpConnect(
              proxyHost: proxy.host.trim(),
              proxyPort: proxy.port,
              targetHost: targetHost,
              targetPort: targetPort,
              username: proxy.username.trim(),
              password: password,
              timeout: timeout,
            );
  }
}

final _sharedSystemResolver = SystemProxyResolver();

/// Configures an [HttpClient] (e.g. for AI requests) to follow [proxy]:
/// - `system`: follows OS system proxy / environment variables.
/// - `direct`: bypasses all proxies.
/// - `custom` HTTP: routes via `PROXY host:port` (+ optional Basic auth).
/// - `custom` SOCKS5: routes via RFC 1928/1929 SOCKS5 using `connectionFactory`
///   with native TLS (`SecureSocket.secure`) for HTTPS.
void configureHttpClientProxy(
  HttpClient client, {
  required ProxySettings proxy,
  String? password,
  SystemProxyResolver? systemResolver,
  Duration connectTimeout = const Duration(seconds: 15),
}) {
  switch (proxy.mode) {
    case ProxyMode.direct:
      client.findProxy = (_) => 'DIRECT';
    case ProxyMode.system:
      final resolver = systemResolver ?? _sharedSystemResolver;
      client.findProxy = resolver.findProxy;
    case ProxyMode.custom:
      if (!proxy.isCustomValid) {
        client.findProxy = (_) => 'DIRECT';
        return;
      }
      final proxyHost = proxy.host.trim();
      final proxyPort = proxy.port;
      final user = proxy.username.trim();
      final pass = password ?? '';
      if (proxy.scheme == ProxyScheme.http) {
        final hp = proxy.formattedHostPort;
        client.findProxy = (url) =>
            isLoopbackHost(url.host) ? 'DIRECT' : 'PROXY $hp';
        if (user.isNotEmpty || pass.isNotEmpty) {
          client.addProxyCredentials(
            proxyHost,
            proxyPort,
            '',
            HttpClientBasicCredentials(user, pass),
          );
        }
      } else {
        // Custom SOCKS5: bypass Dart's HTTP proxy layer and establish a
        // SOCKS5 tunnel per connection, wrapping with TLS when needed.
        client.findProxy = (_) => 'DIRECT';
        client.connectionFactory = (Uri url, String? _, int? _) async {
          if (isLoopbackHost(url.host)) {
            final task = await Socket.startConnect(url.host, url.port);
            if (url.scheme.toLowerCase() != 'https') return task;
            final secured = task.socket.then(
              (s) => SecureSocket.secure(s, host: url.host),
            );
            return ConnectionTask.fromSocket(secured, task.cancel);
          }
          return _startSocks5HttpConnection(
            url: url,
            proxyHost: proxyHost,
            proxyPort: proxyPort,
            username: user,
            password: pass,
            timeout: connectTimeout,
          );
        };
      }
  }
}

/// Tests reachability of a custom proxy server by opening a TCP connection
/// (and validating the SOCKS5 greeting when [ProxyScheme.socks5] is selected).
Future<void> testProxyReachability({
  required ProxySettings proxy,
  String? password,
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (!proxy.isCustomValid) {
    throw const ProxyConnectException('Invalid proxy host or port');
  }
  final socket = await Socket.connect(
    proxy.host.trim(),
    proxy.port,
    timeout: timeout,
  );
  try {
    if (proxy.scheme == ProxyScheme.socks5) {
      final reader = _SocketHandshakeReader(socket);
      try {
        final hasAuth =
            proxy.username.trim().isNotEmpty || (password ?? '').isNotEmpty;
        socket.add(
          hasAuth ? const [0x05, 0x02, 0x00, 0x02] : const [0x05, 0x01, 0x00],
        );
        await socket.flush();
        final reply = await reader.readExact(2, timeout: timeout);
        if (reply[0] != 0x05) {
          throw ProxyConnectException(
            'Not a SOCKS5 server (version ${reply[0]})',
          );
        }
        if (reply[1] == 0xFF) {
          throw const ProxyConnectException(
            'SOCKS5 server rejected authentication method',
          );
        }
        if (reply[1] == 0x02) {
          await _performSocks5UserPassAuth(
            socket,
            reader,
            proxy.username.trim(),
            password ?? '',
            timeout,
          );
        }
      } finally {
        await reader.dispose();
      }
    }
  } finally {
    socket.destroy();
  }
}

/// Opens a raw TCP tunnel through an HTTP CONNECT proxy.
Future<ProxiedSshSocket> connectSshViaHttpConnect({
  required String proxyHost,
  required int proxyPort,
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
  final reader = _SocketHandshakeReader(socket);
  try {
    final hostPart = targetHost.contains(':') && !targetHost.startsWith('[')
        ? '[$targetHost]'
        : targetHost;
    final authority = '$hostPart:$targetPort';
    final buf = StringBuffer()
      ..write('CONNECT $authority HTTP/1.1\r\n')
      ..write('Host: $authority\r\n')
      ..write('Proxy-Connection: Keep-Alive\r\n');
    final user = username ?? '';
    final pass = password ?? '';
    if (user.isNotEmpty || pass.isNotEmpty) {
      final token = base64Encode(utf8.encode('$user:$pass'));
      buf.write('Proxy-Authorization: Basic $token\r\n');
    }
    buf.write('\r\n');
    socket.add(ascii.encode(buf.toString()));
    await socket.flush();

    final headerBytes = await reader.readUntilDelimiter(
      const [0x0D, 0x0A, 0x0D, 0x0A],
      maxBytes: 16 * 1024,
      timeout: timeout,
    );
    final headerText = latin1.decode(headerBytes);
    final firstLine = headerText.split('\r\n').first;
    final match = RegExp(r'^HTTP/\d+\.\d+\s+(\d{3})\b').firstMatch(firstLine);
    final status = match == null ? null : int.tryParse(match.group(1)!);
    if (status == null || status < 200 || status >= 300) {
      throw ProxyConnectException('HTTP proxy rejected CONNECT: $firstLine');
    }

    return reader.detachAsSshSocket();
  } catch (_) {
    await reader.dispose();
    socket.destroy();
    rethrow;
  }
}

/// Opens a raw TCP tunnel through a SOCKS5 proxy (RFC 1928 + RFC 1929 auth).
Future<ProxiedSshSocket> connectSshViaSocks5({
  required String proxyHost,
  required int proxyPort,
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final socket = await Socket.connect(proxyHost, proxyPort, timeout: timeout);
  final reader = _SocketHandshakeReader(socket);
  try {
    final user = username ?? '';
    final pass = password ?? '';
    final hasAuth = user.isNotEmpty || pass.isNotEmpty;

    // 1. Greeting & method negotiation.
    socket.add(
      hasAuth ? const [0x05, 0x02, 0x00, 0x02] : const [0x05, 0x01, 0x00],
    );
    await socket.flush();
    final choice = await reader.readExact(2, timeout: timeout);
    if (choice[0] != 0x05) {
      throw ProxyConnectException('Invalid SOCKS5 version: ${choice[0]}');
    }
    if (choice[1] == 0x02) {
      await _performSocks5UserPassAuth(socket, reader, user, pass, timeout);
    } else if (choice[1] != 0x00) {
      throw ProxyConnectException(
        'SOCKS5 proxy rejected authentication (method 0x${choice[1].toRadixString(16)})',
      );
    }

    // 2. CONNECT request (IPv4 / IPv6 / DOMAINNAME so proxy resolves DNS).
    final req = BytesBuilder(copy: false)
      ..addByte(0x05) // VER
      ..addByte(0x01) // CMD = CONNECT
      ..addByte(0x00); // RSV
    final ip = InternetAddress.tryParse(targetHost);
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      req
        ..addByte(0x01)
        ..add(ip.rawAddress);
    } else if (ip != null && ip.type == InternetAddressType.IPv6) {
      req
        ..addByte(0x04)
        ..add(ip.rawAddress);
    } else {
      final hostBytes = utf8.encode(targetHost);
      if (hostBytes.length > 255) {
        throw const ProxyConnectException(
          'Target hostname too long for SOCKS5',
        );
      }
      req
        ..addByte(0x03)
        ..addByte(hostBytes.length)
        ..add(hostBytes);
    }
    req
      ..addByte((targetPort >> 8) & 0xFF)
      ..addByte(targetPort & 0xFF);
    socket.add(req.toBytes());
    await socket.flush();

    // 3. Read CONNECT reply: VER, REP, RSV, ATYP, BND.ADDR, BND.PORT.
    final head = await reader.readExact(4, timeout: timeout);
    if (head[0] != 0x05) {
      throw ProxyConnectException('Invalid SOCKS5 reply version: ${head[0]}');
    }
    if (head[1] != 0x00) {
      throw ProxyConnectException(
        'SOCKS5 CONNECT failed: ${_socks5ReplyName(head[1])}',
      );
    }
    final atyp = head[3];
    if (atyp == 0x01) {
      await reader.readExact(4 + 2, timeout: timeout);
    } else if (atyp == 0x04) {
      await reader.readExact(16 + 2, timeout: timeout);
    } else if (atyp == 0x03) {
      final len = (await reader.readExact(1, timeout: timeout))[0];
      await reader.readExact(len + 2, timeout: timeout);
    } else {
      throw ProxyConnectException('Unsupported SOCKS5 address type: $atyp');
    }

    return reader.detachAsSshSocket();
  } catch (_) {
    await reader.dispose();
    socket.destroy();
    rethrow;
  }
}

Future<void> _performSocks5UserPassAuth(
  Socket socket,
  _SocketHandshakeReader reader,
  String username,
  String password,
  Duration timeout,
) async {
  final u = utf8.encode(username);
  final p = utf8.encode(password);
  if (u.length > 255 || p.length > 255) {
    throw const ProxyConnectException(
      'SOCKS5 username or password exceeds 255 bytes',
    );
  }
  final msg = BytesBuilder(copy: false)
    ..addByte(0x01) // subnegotiation version
    ..addByte(u.length)
    ..add(u)
    ..addByte(p.length)
    ..add(p);
  socket.add(msg.toBytes());
  await socket.flush();
  final resp = await reader.readExact(2, timeout: timeout);
  if (resp[1] != 0x00) {
    throw const ProxyConnectException('SOCKS5 username/password rejected');
  }
}

String _socks5ReplyName(int code) => switch (code) {
  0x01 => 'general failure',
  0x02 => 'connection not allowed',
  0x03 => 'network unreachable',
  0x04 => 'host unreachable',
  0x05 => 'connection refused',
  0x06 => 'TTL expired',
  0x07 => 'command not supported',
  0x08 => 'address type not supported',
  _ => 'error code 0x${code.toRadixString(16)}',
};

/// Bridges a SOCKS5-tunneled [ProxiedSshSocket] into a fresh un-listened
/// loopback [Socket] (or [SecureSocket] for HTTPS) so `dart:io` [HttpClient]
/// can use SOCKS5 proxies natively with full TLS SNI and cert validation.
Future<ConnectionTask<Socket>> _startSocks5HttpConnection({
  required Uri url,
  required String proxyHost,
  required int proxyPort,
  required String username,
  required String password,
  required Duration timeout,
}) async {
  var cancelled = false;
  ProxiedSshSocket? tunnel;
  ServerSocket? bridgeServer;
  Socket? bridgePeer;

  Future<Socket> open() async {
    final targetPort = url.hasPort
        ? url.port
        : (url.scheme.toLowerCase() == 'https' ? 443 : 80);
    tunnel = await connectSshViaSocks5(
      proxyHost: proxyHost,
      proxyPort: proxyPort,
      targetHost: url.host,
      targetPort: targetPort,
      username: username,
      password: password,
      timeout: timeout,
    );
    if (cancelled) {
      tunnel!.destroy();
      throw const SocketException('Connection cancelled');
    }

    bridgeServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final acceptedFuture = bridgeServer!.first;
    final clientSock = await Socket.connect(
      InternetAddress.loopbackIPv4,
      bridgeServer!.port,
      timeout: timeout,
    );
    bridgePeer = await acceptedFuture;
    await bridgeServer!.close();
    bridgeServer = null;

    if (cancelled) {
      clientSock.destroy();
      bridgePeer!.destroy();
      tunnel!.destroy();
      throw const SocketException('Connection cancelled');
    }

    _pumpBridge(bridgePeer!, tunnel!);

    if (url.scheme.toLowerCase() == 'https') {
      return SecureSocket.secure(clientSock, host: url.host);
    }
    return clientSock;
  }

  return ConnectionTask.fromSocket(open(), () {
    cancelled = true;
    unawaited(bridgeServer?.close());
    bridgePeer?.destroy();
    tunnel?.destroy();
  });
}

void _pumpBridge(Socket local, ProxiedSshSocket remote) {
  var closed = false;
  StreamSubscription<Uint8List>? localSub;
  StreamSubscription<Uint8List>? remoteSub;
  var localDone = false;
  var remoteDone = false;

  void cleanup({bool destroy = false}) {
    if (closed) return;
    closed = true;
    unawaited(localSub?.cancel());
    unawaited(remoteSub?.cancel());
    if (destroy) {
      local.destroy();
      remote.destroy();
    } else {
      unawaited(local.close().catchError((Object _) {}));
      unawaited(remote.close().catchError((Object _) {}));
    }
  }

  unawaited(local.done.catchError((Object _) {}));
  unawaited(remote.done.catchError((Object _) {}));

  localSub = local.listen(
    (chunk) {
      if (closed) return;
      try {
        remote.sink.add(chunk);
      } catch (_) {
        cleanup(destroy: true);
      }
    },
    onDone: () {
      localDone = true;
      unawaited(remote.sink.close().catchError((Object _) {}));
      if (remoteDone) cleanup();
    },
    onError: (Object _) => cleanup(destroy: true),
    cancelOnError: true,
  );

  remoteSub = remote.stream.listen(
    (chunk) {
      if (closed) return;
      try {
        local.add(chunk);
      } catch (_) {
        cleanup(destroy: true);
      }
    },
    onDone: () {
      remoteDone = true;
      unawaited(local.close().catchError((Object _) {}));
      if (localDone) cleanup();
    },
    onError: (Object _) => cleanup(destroy: true),
    cancelOnError: true,
  );
}

/// Reads exact byte counts or delimited headers from a [Socket] during a proxy
/// handshake, then hands the live subscription plus any already-buffered
/// trailing bytes directly to a [ProxiedSshSocket] without dropping a byte.
class _SocketHandshakeReader {
  _SocketHandshakeReader(this._socket) {
    _sub = _socket.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _sub;
  final _buffer = <int>[];
  Completer<void>? _waiter;
  Object? _error;
  bool _eof = false;
  StreamController<Uint8List>? _forwarded;

  void _onData(Uint8List chunk) {
    final forwarded = _forwarded;
    if (forwarded != null) {
      if (!forwarded.isClosed) forwarded.add(chunk);
      return;
    }
    _buffer.addAll(chunk);
    _wake();
  }

  void _onDone() {
    _eof = true;
    final forwarded = _forwarded;
    if (forwarded != null) {
      if (!forwarded.isClosed) unawaited(forwarded.close());
      return;
    }
    _wake();
  }

  void _onError(Object err, StackTrace st) {
    _error = err;
    final forwarded = _forwarded;
    if (forwarded != null) {
      if (!forwarded.isClosed) {
        forwarded.addError(err, st);
        unawaited(forwarded.close());
      }
      return;
    }
    _wake();
  }

  void _wake() {
    final w = _waiter;
    if (w != null && !w.isCompleted) {
      _waiter = null;
      w.complete();
    }
  }

  Future<void> _waitForMore(DateTime deadline) async {
    if (_error != null) throw _error!;
    if (_eof) {
      throw const ProxyConnectException(
        'Proxy closed connection during handshake',
      );
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Proxy handshake timed out');
    }
    final c = _waiter ??= Completer<void>();
    await c.future.timeout(remaining);
  }

  Future<Uint8List> readExact(int count, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < count) {
      await _waitForMore(deadline);
    }
    final out = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return out;
  }

  Future<Uint8List> readUntilDelimiter(
    List<int> delimiter, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var scanFrom = 0;
    while (true) {
      final idx = _indexOf(_buffer, delimiter, scanFrom);
      if (idx >= 0) {
        final end = idx + delimiter.length;
        final out = Uint8List.fromList(_buffer.sublist(0, end));
        _buffer.removeRange(0, end);
        return out;
      }
      if (_buffer.length > maxBytes) {
        throw const ProxyConnectException('Proxy response header too large');
      }
      scanFrom = (_buffer.length - delimiter.length).clamp(0, _buffer.length);
      await _waitForMore(deadline);
    }
  }

  static int _indexOf(List<int> haystack, List<int> needle, int start) {
    final limit = haystack.length - needle.length;
    for (var i = start; i <= limit; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  ProxiedSshSocket detachAsSshSocket() {
    final controller = StreamController<Uint8List>();
    _forwarded = controller;
    if (_buffer.isNotEmpty) {
      controller.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }
    if (_error != null) {
      controller.addError(_error!);
      unawaited(controller.close());
    } else if (_eof) {
      unawaited(controller.close());
    }
    return ProxiedSshSocket._(_socket, controller.stream, () async {
      await _sub.cancel();
      if (!controller.isClosed) await controller.close();
    });
  }

  Future<void> dispose() async {
    await _sub.cancel();
  }
}
