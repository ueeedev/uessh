import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../core/app_log.dart';
import 'mcp_tools.dart';

/// Embedded local MCP server over loopback HTTP (`127.0.0.1` only).
///
/// Supports both:
/// - **Streamable HTTP** (`POST /mcp`, `DELETE /mcp`, `GET /mcp`) per MCP
///   2025-03-26 / 2024-11-05
/// - **Legacy HTTP+SSE** (`GET /sse` + `POST /messages?sessionId=...`)
///
/// Every request must:
/// 1. Target a loopback `Host` header (DNS rebinding defence).
/// 2. Omit `Origin` or supply a loopback `Origin` (browser CSRF defence).
/// 3. Carry `Authorization: Bearer <token>` matching [token].
class McpServer {
  McpServer({
    required this.executor,
    required this.token,
    this.serverVersion = '0.1.7',
  });

  static const supportedProtocolVersions = [
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];
  static const _maxBodyBytes = 256 * 1024;

  final McpToolExecutor executor;
  final String token;
  final String serverVersion;

  HttpServer? _server;
  final _mcpSessions = <String>{};
  final _sseClients = <String, _SseClient>{};

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start(int port) async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    log.info('mcp', 'MCP server listening on 127.0.0.1:${server.port}');
    unawaited(
      server.forEach((request) {
        unawaited(_handleRequest(request));
      }),
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final client in _sseClients.values.toList()) {
      await client.close();
    }
    _sseClients.clear();
    _mcpSessions.clear();
    if (server != null) {
      await server.close(force: true);
      log.info('mcp', 'MCP server stopped');
    }
  }

  /// Generates a cryptographically random 32-byte hex bearer token.
  static String generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }

  /// Ready-to-paste client configuration snippet for Streamable HTTP MCP.
  static String clientConfigJson({required int port, required String token}) =>
      const JsonEncoder.withIndent('  ').convert({
        'mcpServers': {
          'uessh': {
            'url': 'http://127.0.0.1:$port/mcp',
            'headers': {'Authorization': 'Bearer $token'},
          },
        },
      });

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      // 1. Loopback Host check (defends against DNS rebinding).
      final host = request.headers.value(HttpHeaders.hostHeader);
      if (!_isLoopbackHost(host)) {
        _sendText(response, HttpStatus.forbidden, 'Forbidden host');
        return;
      }

      // 2. Origin check (defends against cross-site browser requests).
      final origin = request.headers.value('origin');
      if (origin != null && !_isLoopbackOrigin(origin)) {
        _sendText(response, HttpStatus.forbidden, 'Forbidden origin');
        return;
      }

      // 3. Bearer token authentication.
      if (!_authorized(request)) {
        response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer realm="uessh-mcp"',
        );
        _sendText(response, HttpStatus.unauthorized, 'Unauthorized');
        return;
      }

      final path = request.uri.path;
      if (path == '/mcp') {
        await _handleStreamableHttp(request);
      } else if (path == '/sse' && request.method == 'GET') {
        await _handleSseConnect(request);
      } else if (path == '/messages' && request.method == 'POST') {
        await _handleSseMessage(request);
      } else if (path == '/health' && request.method == 'GET') {
        _sendJson(response, HttpStatus.ok, {
          'status': 'ok',
          'server': 'uessh',
          'version': serverVersion,
        });
      } else {
        _sendText(response, HttpStatus.notFound, 'Not found');
      }
    } catch (e, st) {
      log.error('mcp', 'Unhandled HTTP error', e, st);
      try {
        _sendJson(response, HttpStatus.internalServerError, {
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32603, 'message': 'Internal server error'},
        });
      } catch (_) {}
    }
  }

  Future<void> _handleStreamableHttp(HttpRequest request) async {
    final response = request.response;
    if (request.method == 'DELETE') {
      final sid = request.headers.value('mcp-session-id');
      if (sid != null) _mcpSessions.remove(sid);
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }
    if (request.method == 'GET') {
      // Stateless Streamable HTTP server: server-initiated GET streams aren't
      // needed, so 405 signals clients to use POST.
      response.headers.set(HttpHeaders.allowHeader, 'POST, DELETE');
      _sendText(response, HttpStatus.methodNotAllowed, 'Use POST /mcp');
      return;
    }
    if (request.method != 'POST') {
      response.headers.set(HttpHeaders.allowHeader, 'POST, DELETE');
      _sendText(response, HttpStatus.methodNotAllowed, 'Method not allowed');
      return;
    }

    final body = await _readBody(request);
    if (body == null) {
      _sendText(
        response,
        HttpStatus.requestEntityTooLarge,
        'Request body too large',
      );
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      _sendJson(
        response,
        HttpStatus.badRequest,
        _rpcError(null, -32700, 'Parse error'),
      );
      return;
    }

    String? newSessionId;
    if (decoded is Map<String, Object?>) {
      if (decoded['method'] == 'initialize') {
        newSessionId = _newSessionId();
        _mcpSessions.add(newSessionId);
      }
      final result = await _dispatchOne(decoded);
      if (newSessionId != null) {
        response.headers.set('Mcp-Session-Id', newSessionId);
      }
      if (result == null) {
        response.statusCode = HttpStatus.accepted;
        await response.close();
      } else {
        _sendJson(response, HttpStatus.ok, result);
      }
      return;
    }

    if (decoded is List) {
      if (decoded.isEmpty) {
        _sendJson(
          response,
          HttpStatus.badRequest,
          _rpcError(null, -32600, 'Invalid Request'),
        );
        return;
      }
      final responses = <Map<String, Object?>>[];
      for (final item in decoded) {
        if (item is! Map<String, Object?>) {
          responses.add(_rpcError(null, -32600, 'Invalid Request'));
          continue;
        }
        if (item['method'] == 'initialize' && newSessionId == null) {
          newSessionId = _newSessionId();
          _mcpSessions.add(newSessionId);
        }
        final r = await _dispatchOne(item);
        if (r != null) responses.add(r);
      }
      if (newSessionId != null) {
        response.headers.set('Mcp-Session-Id', newSessionId);
      }
      if (responses.isEmpty) {
        response.statusCode = HttpStatus.accepted;
        await response.close();
      } else {
        _sendJson(response, HttpStatus.ok, responses);
      }
      return;
    }

    _sendJson(
      response,
      HttpStatus.badRequest,
      _rpcError(null, -32600, 'Invalid Request'),
    );
  }

  Future<void> _handleSseConnect(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    response.bufferOutput = false;

    final id = _newSessionId();
    final client = _SseClient(id: id, response: response);
    _sseClients[id] = client;
    client.sendEvent('endpoint', '/messages?sessionId=$id');

    unawaited(
      response.done.whenComplete(() {
        _sseClients.remove(id);
        client.disposeTimer();
      }),
    );
  }

  Future<void> _handleSseMessage(HttpRequest request) async {
    final response = request.response;
    final id = request.uri.queryParameters['sessionId'];
    final client = id == null ? null : _sseClients[id];
    if (client == null) {
      _sendText(response, HttpStatus.notFound, 'Unknown SSE session');
      return;
    }

    final body = await _readBody(request);
    if (body == null) {
      _sendText(
        response,
        HttpStatus.requestEntityTooLarge,
        'Request body too large',
      );
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      _sendJson(
        response,
        HttpStatus.badRequest,
        _rpcError(null, -32700, 'Parse error'),
      );
      return;
    }

    // Acknowledge immediately per legacy HTTP+SSE transport; push reply on SSE.
    response.statusCode = HttpStatus.accepted;
    await response.close();

    if (decoded is Map<String, Object?>) {
      final result = await _dispatchOne(decoded);
      if (result != null) {
        client.sendEvent('message', jsonEncode(result));
      }
    }
  }

  Future<Map<String, Object?>?> _dispatchOne(Map<String, Object?> msg) async {
    final jsonrpc = msg['jsonrpc'];
    final method = msg['method'];
    final hasId = msg.containsKey('id');
    final id = msg['id'];

    if (jsonrpc != '2.0' || method is! String) {
      return hasId ? _rpcError(id, -32600, 'Invalid Request') : null;
    }

    // Notifications carry no `id` and expect no JSON-RPC response.
    if (!hasId) {
      return null;
    }

    final rawParams = msg['params'];
    final params = rawParams is Map
        ? rawParams.cast<String, Object?>()
        : const <String, Object?>{};

    switch (method) {
      case 'initialize':
        final requested = params['protocolVersion'];
        final negotiated =
            requested is String && supportedProtocolVersions.contains(requested)
            ? requested
            : supportedProtocolVersions.first;
        return _rpcResult(id, {
          'protocolVersion': negotiated,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'uessh', 'version': serverVersion},
        });
      case 'ping':
        return _rpcResult(id, <String, Object?>{});
      case 'tools/list':
        return _rpcResult(id, {'tools': mcpToolDefinitions});
      case 'tools/call':
        final toolName = params['name'];
        if (toolName is! String || toolName.isEmpty) {
          return _rpcError(id, -32602, 'Missing tool "name"');
        }
        final rawArgs = params['arguments'];
        if (rawArgs != null && rawArgs is! Map) {
          return _rpcError(id, -32602, 'Tool "arguments" must be an object');
        }
        final args = rawArgs is Map
            ? rawArgs.cast<String, Object?>()
            : const <String, Object?>{};
        final toolResult = await executor.call(toolName, args);
        return _rpcResult(id, toolResult.toJson());
      default:
        return _rpcError(id, -32601, 'Method not found: $method');
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null) return false;
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return false;
    final offered = header.substring(prefix.length);
    return _constantTimeEquals(offered, token);
  }

  Future<String?> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      if (builder.length + chunk.length > _maxBodyBytes) {
        return null;
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  void _sendJson(HttpResponse response, int status, Object body) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }

  void _sendText(HttpResponse response, int status, String text) {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(text);
    response.close();
  }

  static Map<String, Object?> _rpcResult(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _rpcError(Object? id, int code, String message) =>
      {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  static String _newSessionId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }

  static bool _isLoopbackHost(String? host) {
    if (host == null || host.isEmpty) return false;
    final lower = host.toLowerCase();
    // Accept 127.0.0.1[:port], localhost[:port], [::1][:port].
    if (lower == 'localhost' || lower.startsWith('localhost:')) return true;
    if (lower == '127.0.0.1' || lower.startsWith('127.0.0.1:')) return true;
    if (lower == '[::1]' || lower.startsWith('[::1]:')) return true;
    return false;
  }

  static bool _isLoopbackOrigin(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final h = uri.host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  static bool _constantTimeEquals(String a, String b) {
    final ba = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = ba.length ^ bb.length;
    final len = ba.length < bb.length ? ba.length : bb.length;
    for (var i = 0; i < len; i++) {
      diff |= ba[i] ^ bb[i];
    }
    return diff == 0;
  }
}

class _SseClient {
  _SseClient({required this.id, required this.response}) {
    _keepAlive = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed) return;
      try {
        response.write(': ping\n\n');
      } catch (_) {
        disposeTimer();
      }
    });
  }

  final String id;
  final HttpResponse response;
  Timer? _keepAlive;
  bool _closed = false;

  void sendEvent(String event, String data) {
    if (_closed) return;
    try {
      response.write('event: $event\ndata: $data\n\n');
    } catch (_) {
      disposeTimer();
    }
  }

  void disposeTimer() {
    _closed = true;
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  Future<void> close() async {
    disposeTimer();
    try {
      await response.close();
    } catch (_) {}
  }
}
