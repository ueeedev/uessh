import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../hosts/host.dart';
import '../hosts/host_repository.dart';
import 'known_hosts.dart';

enum SessionStatus { connecting, connected, failed, closed }

/// Questions a session may need to ask the user while connecting.
abstract class SessionPrompts {
  Future<bool> confirmHostKey({
    required String hostPort,
    required KnownHostEntry offered,
    KnownHostEntry? previous,
  });

  /// Returns null if the user cancels.
  Future<String?> askSecret({required String title, required String message});
}

/// One SSH connection with its terminal buffer.
class TerminalSession extends ChangeNotifier {
  TerminalSession({
    required this.host,
    required this.repository,
    required this.knownHosts,
    required this.prompts,
  }) : terminal = Terminal(maxLines: 10000, platform: _terminalPlatform()) {
    terminal.onTitleChange = (t) {
      title = t;
      notifyListeners();
    };
  }

  final String id = Host.newId();
  final Host host;
  final HostRepository repository;
  final KnownHostsStore knownHosts;
  final SessionPrompts prompts;

  final Terminal terminal;
  final TerminalController controller = TerminalController();

  SessionStatus status = SessionStatus.connecting;
  String? error;

  /// Window title set by the remote shell (e.g. `user@server: ~`).
  String? title;

  /// When the current connection's shell opened.
  DateTime? connectedAt;

  SSHClient? _client;
  SSHSession? _shell;
  final _subs = <StreamSubscription<String>>[];

  // Bumped on every connect/close so callbacks from an old connection
  // are ignored after reconnecting.
  int _generation = 0;
  bool _disposed = false;

  Future<void> connect() async {
    _teardown();
    final gen = ++_generation;
    _setStatus(SessionStatus.connecting);
    terminal.write('\x1b[2m正在连接 ${host.target} …\x1b[0m\r\n');

    try {
      final secrets = await repository.readSecrets(host.id);

      List<SSHKeyPair>? identities;
      if (host.authMethod == AuthMethod.key) {
        identities = await _loadKeyPairs(secrets);
      }

      final socket = await SSHSocket.connect(
        host.address,
        host.port,
        timeout: const Duration(seconds: 10),
      );
      if (gen != _generation) {
        socket.destroy();
        return;
      }

      // Ask for a password at most once per attempt, even if the server
      // tries both "password" and "keyboard-interactive".
      Future<String?>? password;
      Future<String?> getPassword() => password ??= _resolvePassword(secrets);

      final client = SSHClient(
        socket,
        username: host.username,
        identities: identities,
        onPasswordRequest: host.authMethod == AuthMethod.password
            ? getPassword
            : null,
        onUserInfoRequest: host.authMethod == AuthMethod.password
            ? (req) => _answerKeyboardInteractive(req, getPassword)
            : null,
        onVerifyHostKey: (type, fingerprint) => knownHosts.verify(
          address: host.address,
          port: host.port,
          keyType: type,
          fingerprint: fingerprint,
          prompt: prompts.confirmHostKey,
        ),
        onUserauthBanner: (banner) =>
            terminal.write(banner.replaceAll('\n', '\r\n')),
        keepAliveInterval: const Duration(seconds: 30),
      );
      _client = client;
      // Socket errors after login surface here; handled via shell.done too.
      client.done.catchError((Object _) {});

      await client.authenticated;
      if (gen != _generation) return;

      final shell = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      if (gen != _generation) {
        shell.close();
        return;
      }
      _shell = shell;

      for (final stream in [shell.stdout, shell.stderr]) {
        _subs.add(
          stream
              .cast<List<int>>()
              .transform(const Utf8Decoder(allowMalformed: true))
              .listen(terminal.write),
        );
      }
      terminal.onOutput = (data) => shell.write(utf8.encode(data));
      terminal.onResize = (w, h, pw, ph) => shell.resizeTerminal(w, h, pw, ph);

      connectedAt = DateTime.now();
      _setStatus(SessionStatus.connected);

      unawaited(
        shell.done.then(
          (_) => _onRemoteClosed(gen),
          onError: (Object _) => _onRemoteClosed(gen),
        ),
      );
    } catch (e) {
      if (gen != _generation) return;
      _teardown();
      error = describeConnectError(e, host);
      terminal.write('\r\n\x1b[31m$error\x1b[0m\r\n');
      _setStatus(SessionStatus.failed);
    }
  }

  /// Runs [command] on a separate channel of this connection (nothing
  /// shows in the terminal) and returns its stdout, or null if not
  /// connected, it fails, or it takes longer than [timeout].
  Future<String?> runCommand(
    String command, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = _client;
    if (client == null || status != SessionStatus.connected) return null;
    try {
      final out = await client.run(command, stderr: false).timeout(timeout);
      return utf8.decode(out, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  void close() {
    _generation++;
    _teardown();
    if (status != SessionStatus.failed) _setStatus(SessionStatus.closed);
  }

  @override
  void dispose() {
    close();
    _disposed = true;
    controller.dispose();
    super.dispose();
  }

  Future<List<SSHKeyPair>> _loadKeyPairs(HostSecrets secrets) async {
    final pem = secrets.privateKey;
    if (pem == null || pem.trim().isEmpty) {
      throw const _ConnectError('这台主机没有保存私钥，请先编辑主机并导入私钥');
    }
    var passphrase = secrets.passphrase;
    if (SSHKeyPair.isEncryptedPem(pem) && (passphrase ?? '').isEmpty) {
      passphrase = await prompts.askSecret(
        title: '输入私钥口令',
        message: '${host.displayName} 的私钥已加密',
      );
      if (passphrase == null) throw const _ConnectError('已取消登录');
    }
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  Future<String?> _resolvePassword(HostSecrets secrets) async {
    final saved = secrets.password;
    if (saved != null && saved.isNotEmpty) return saved;
    return prompts.askSecret(title: '输入密码', message: '登录 ${host.target}');
  }

  Future<List<String>?> _answerKeyboardInteractive(
    SSHUserInfoRequest request,
    Future<String?> Function() getPassword,
  ) async {
    final answers = <String>[];
    var passwordUsed = false;
    for (final p in request.prompts) {
      String? answer;
      if (!p.echo && !passwordUsed) {
        // The usual case: a single hidden "Password:" prompt.
        passwordUsed = true;
        answer = await getPassword();
      } else {
        answer = await prompts.askSecret(
          title: request.name.isNotEmpty ? request.name : '服务器验证',
          message: p.promptText.trim(),
        );
      }
      if (answer == null) return null;
      answers.add(answer);
    }
    return answers;
  }

  void _onRemoteClosed(int gen) {
    if (gen != _generation || _disposed) return;
    _teardown();
    terminal.write('\r\n\x1b[2m[连接已关闭]\x1b[0m\r\n');
    _setStatus(SessionStatus.closed);
  }

  void _teardown() {
    connectedAt = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    terminal.onOutput = null;
    terminal.onResize = null;
    _shell?.close();
    _shell = null;
    _client?.close();
    _client = null;
  }

  void _setStatus(SessionStatus s) {
    if (_disposed) return;
    status = s;
    if (s != SessionStatus.failed) error = null;
    notifyListeners();
  }

  static TerminalTargetPlatform _terminalPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return TerminalTargetPlatform.macos;
      case TargetPlatform.windows:
        return TerminalTargetPlatform.windows;
      case TargetPlatform.linux:
        return TerminalTargetPlatform.linux;
      default:
        return TerminalTargetPlatform.unknown;
    }
  }
}

class _ConnectError implements Exception {
  const _ConnectError(this.message);
  final String message;
}

/// Turns connection failures into a short message for the user.
String describeConnectError(Object e, Host host) {
  if (e is _ConnectError) return e.message;
  if (e is SocketException) {
    final reason = e.osError?.message ?? e.message;
    return '无法连接到 ${host.address}:${host.port}（$reason）';
  }
  if (e is TimeoutException) return '连接 ${host.address}:${host.port} 超时';
  if (e is SSHAuthAbortError) return '已取消登录';
  if (e is SSHAuthFailError) return '认证失败：用户名、密码或密钥不正确';
  if (e is SSHHostkeyError) return '主机密钥未被信任，已断开连接';
  if (e is SSHKeyDecryptError) return '私钥口令不正确';
  if (e is SSHKeyDecodeError) return '无法识别私钥格式';
  if (e is SSHError) return 'SSH 错误：$e';
  return '连接失败：$e';
}
