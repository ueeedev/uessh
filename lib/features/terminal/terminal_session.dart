import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm2/xterm.dart';

import '../../core/app_log.dart';

import '../hosts/host.dart';
import '../hosts/host_repository.dart';
import '../keys/ssh_key.dart';
import '../ai/command_safety.dart' show visibleCommand;
import '../files/remote_fs.dart';
import 'command_highlight.dart';
import 'known_hosts.dart';
import '../../l10n/l10n.dart';

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
    this.keys,
  }) : terminal = Terminal(maxLines: 10000, platform: _terminalPlatform()) {
    highlighter = CommandHighlighter(
      terminal,
      () =>
          highlightSettings?.call() ??
          (enabled: false, colors: const <HighlightToken, int>{}),
    );
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

  /// Saved keys (Keys page), for hosts that use one.
  final KeyRepository? keys;

  final Terminal terminal;
  final TerminalController controller = TerminalController();

  SessionStatus status = SessionStatus.connecting;
  String? error;

  /// Window title set by the remote shell (e.g. `user@server: ~`).
  String? title;

  /// When the current connection's shell opened.
  DateTime? connectedAt;

  /// Called with what the user types here (broadcast input to other
  /// panes uses it).
  void Function(String data)? onUserInput;

  /// Colors the command being typed (settings read each time).
  late final CommandHighlighter highlighter;
  HighlightSettings Function()? highlightSettings;

  /// Called when the user presses Enter here (the file browser follows
  /// `cd` with it).
  void Function()? onCommandEntered;

  Future<RemoteFs>? _fs;

  /// SFTP access to this connection's server, opened on first use.
  Future<RemoteFs> remoteFs() {
    final client = _client;
    if (client == null || status != SessionStatus.connected) {
      return Future.error(StateError('not connected'));
    }
    final existing = _fs;
    if (existing != null) return existing;
    final opening = client.sftp().then<RemoteFs>(SftpRemoteFs.new);
    _fs = opening;
    // A failed open is retried next time.
    opening.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_fs, opening)) _fs = null;
      },
    );
    return opening;
  }

  /// Test switch: open shells without [shellMarkerVar], as on servers
  /// that refuse it.
  @visibleForTesting
  static bool debugNoShellMarker = false;

  /// Servers that refused [shellMarkerVar] (asked only once per run).
  static final _noEnvServers = <String>{};

  /// Whether this shell carries [shellMarkerVar].
  bool _markerSet = false;

  /// Server clock (epoch seconds) when the shell opened, to find it by
  /// start time when it carries no marker.
  int? _shellStartedAt;

  Future<void> _recordShellStart(int gen) async {
    try {
      final r = await exec('date +%s', timeout: const Duration(seconds: 5));
      if (gen == _generation) _shellStartedAt = int.tryParse(r.stdout.trim());
    } catch (_) {}
  }

  /// The folder this tab's shell is in (Linux), or null if it can't be
  /// told. Found by [shellMarkerVar] when the server took it, otherwise as
  /// the newest shell on the terminal of the login shell started closest
  /// to when this one opened.
  Future<String?> shellCwd() async {
    try {
      final script = _markerSet
          ? shellCwdScript(id)
          : shellCwdByStartScript(_shellStartedAt);
      final r = await exec(
        'sh -c ${shellQuote(script)}',
        timeout: const Duration(seconds: 5),
      );
      final cwd = r.stdout.trim();
      return cwd.startsWith('/') ? cwd : null;
    } catch (_) {
      return null;
    }
  }

  /// Test hook: sees everything [sendInput] sends.
  @visibleForTesting
  void Function(String data)? debugOnSend;

  /// Sends [data] to the shell as if typed here (not passed on to
  /// [onUserInput], so broadcasting can't loop).
  void sendInput(String data) {
    debugOnSend?.call(data);
    highlighter.onInput(data);
    _shell?.write(utf8.encode(data));
  }

  SSHClient? _client;
  SSHSession? _shell;
  final _subs = <StreamSubscription<String>>[];

  // Bumped on every connect/close so callbacks from an old connection
  // are ignored after reconnecting.
  int _generation = 0;
  bool _disposed = false;

  // --- Auto-reconnect ---

  /// How to reconnect after an unexpected drop (from the settings, read
  /// each time). Null: never.
  ReconnectPolicy Function()? reconnectPolicy;

  /// The automatic attempt waiting or running (1-based); 0 when none.
  int reconnectAttempt = 0;

  /// Attempts allowed in this round (shown as "2/3").
  int reconnectTotal = 0;

  /// When the waiting attempt starts.
  DateTime? reconnectAt;
  Timer? _reconnectTimer;

  bool get reconnectPending => _reconnectTimer?.isActive ?? false;

  /// Stops waiting to reconnect.
  void cancelReconnect() {
    if (_reconnectTimer == null && reconnectAttempt == 0) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectAttempt = 0;
    reconnectAt = null;
    if (!_disposed) notifyListeners();
  }

  /// Plans the next automatic attempt, or gives up when they're used up
  /// (or turned off). Returns whether one was planned.
  bool _scheduleReconnect() {
    final p = reconnectPolicy?.call();
    if (_disposed ||
        p == null ||
        !p.enabled ||
        reconnectAttempt >= p.attempts) {
      if (reconnectAttempt > 0) {
        terminal.write(
          '\x1b[31m${currentL10n.reconnectGaveUp(reconnectAttempt)}\x1b[0m\r\n',
        );
        log.info('ssh', 'Gave up reconnecting to ${host.target}');
      }
      reconnectAttempt = 0;
      reconnectAt = null;
      return false;
    }
    reconnectAttempt++;
    reconnectTotal = p.attempts;
    reconnectAt = DateTime.now().add(p.delay);
    terminal.write(
      '\x1b[2m${currentL10n.reconnectingIn(p.delay.inSeconds, reconnectAttempt, p.attempts)}\x1b[0m\r\n',
    );
    log.info(
      'ssh',
      'Reconnecting to ${host.target} in ${p.delay.inSeconds}s '
          '($reconnectAttempt/${p.attempts})',
    );
    _reconnectTimer = Timer(p.delay, () {
      _reconnectTimer = null;
      reconnectAt = null;
      if (!_disposed) connect(auto: true);
    });
    if (!_disposed) notifyListeners();
    return true;
  }

  /// Connects. [auto]: an automatic reconnect attempt (others reset the
  /// count).
  Future<void> connect({bool auto = false}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!auto) reconnectAttempt = 0;
    _teardown();
    final gen = ++_generation;
    _setStatus(SessionStatus.connecting);
    log.info('ssh', 'Connecting to ${host.target}');
    terminal.write(
      '\x1b[2m${currentL10n.connectingTo(host.target)}\x1b[0m\r\n',
    );

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

      final pty = SSHPtyConfig(
        width: terminal.viewWidth,
        height: terminal.viewHeight,
      );
      // Marks this shell (and what it starts) so its current folder can be
      // found later (see shellCwd). Servers that don't accept the variable
      // (no AcceptEnv LC_*) refuse the request; then the shell opens
      // without it and is found another way.
      final serverKey = '${host.address}:${host.port}';
      SSHSession shell;
      if (_noEnvServers.contains(serverKey) || debugNoShellMarker) {
        shell = await client.shell(pty: pty);
        _markerSet = false;
      } else {
        try {
          shell = await client.shell(
            pty: pty,
            environment: {shellMarkerVar: id},
          );
          _markerSet = true;
        } on SSHChannelRequestError catch (e) {
          log.info('ssh', '${host.target} refused $shellMarkerVar ($e)');
          _noEnvServers.add(serverKey);
          if (gen != _generation) return;
          shell = await client.shell(pty: pty);
          _markerSet = false;
        }
      }
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
              .listen((data) {
                terminal.write(data);
                highlighter.afterOutput();
              }),
        );
      }
      terminal.onOutput = (data) {
        highlighter.onInput(data);
        shell.write(utf8.encode(data));
        onUserInput?.call(data);
        if (data.contains('\r')) onCommandEntered?.call();
      };
      terminal.onResize = (w, h, pw, ph) => shell.resizeTerminal(w, h, pw, ph);

      connectedAt = DateTime.now();
      log.info('ssh', 'Connected to ${host.target}');
      reconnectAttempt = 0;
      reconnectAt = null;
      _setStatus(SessionStatus.connected);
      if (!_markerSet) unawaited(_recordShellStart(gen));

      unawaited(
        shell.done.then(
          (_) => _onRemoteClosed(gen, shell),
          onError: (Object _) => _onRemoteClosed(gen, shell),
        ),
      );
    } catch (e) {
      if (gen != _generation) return;
      _teardown();
      error = describeConnectError(e, host);
      log.warn('ssh', 'Connection to ${host.target} failed: $e');
      terminal.write('\r\n\x1b[31m$error\x1b[0m\r\n');
      _setStatus(SessionStatus.failed);
      // Keep trying only when it may come back by itself (network, server
      // restarting) - not after a wrong password or a refused host key.
      if (auto && _worthRetrying(e)) {
        _scheduleReconnect();
      } else if (auto) {
        reconnectAttempt = 0;
        notifyListeners();
      }
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

  /// Runs [command] on its own channel (not in the terminal) and returns
  /// stdout, stderr and the exit code. Output beyond [maxBytes] per stream
  /// is dropped; after [timeout] the command is killed. Throws
  /// [StateError] when not connected.
  Future<CommandResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 60),
    int maxBytes = 64 * 1024,
    void Function(String text)? onStdout,
    void Function(String text)? onStderr,
    Future<void>? cancel,
  }) async {
    final client = _client;
    if (client == null || status != SessionStatus.connected) {
      throw StateError('not connected');
    }
    final channel = await client.execute(command);
    final out = <int>[], err = <int>[];
    var truncated = false;
    void collect(List<int> into, List<int> chunk) {
      final room = maxBytes - into.length;
      if (room <= 0) {
        truncated = true;
      } else if (chunk.length > room) {
        into.addAll(chunk.take(room));
        truncated = true;
      } else {
        into.addAll(chunk);
      }
    }

    // Live copies for [onStdout] / [onStderr], decoded across chunk
    // boundaries.
    ByteConversionSink? live(void Function(String)? f) => f == null
        ? null
        : const Utf8Decoder(allowMalformed: true)
              .startChunkedConversion(_FnSink(f));
    final liveOut = live(onStdout), liveErr = live(onStderr);
    final subs = [
      channel.stdout.listen((c) {
        final before = out.length;
        collect(out, c);
        if (out.length > before) liveOut?.add(out.sublist(before));
      }),
      channel.stderr.listen((c) {
        final before = err.length;
        collect(err, c);
        if (err.length > before) liveErr?.add(err.sublist(before));
      }),
    ];
    var timedOut = false;
    // Stop (e.g. the AI panel's Stop button): end the command on the
    // server too, not just stop waiting for it.
    cancel?.then((_) {
      try {
        channel.kill(SSHSignal.TERM);
      } catch (_) {}
      channel.close();
    });
    try {
      await channel.done.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      channel.kill(SSHSignal.KILL);
      channel.close();
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      liveOut?.close();
      liveErr?.close();
    }
    return CommandResult(
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
      exitCode: channel.exitCode,
      truncated: truncated,
      timedOut: timedOut,
    );
  }

  /// Runs [command] like [exec] and shows it in this terminal while it
  /// runs: a "[AI] $ command" line, the output as it arrives, then the
  /// exit code. The shell isn't involved (it runs on its own channel);
  /// afterwards the line the cursor was on (the prompt and anything typed)
  /// is drawn again so the shell's view of the screen still matches.
  /// Skipped while a full-screen program (vim, top) owns the screen.
  Future<CommandResult> execShown(
    String command, {
    String label = 'AI',
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancel,
  }) async {
    if (terminal.isUsingAltBuffer) {
      return exec(command, timeout: timeout, cancel: cancel);
    }
    final buffer = terminal.buffer;
    final promptLine = buffer.lines[buffer.absoluteCursorY]
        .getText()
        .trimRight();
    final cursorX = buffer.cursorX;
    var atLineStart = true;
    void show(String text, {String? color}) {
      if (text.isEmpty) return;
      final crlf = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      terminal.write(color == null ? crlf : '$color$crlf\x1b[0m');
      atLineStart = text.endsWith('\n');
    }

    // Control and bidi characters are shown, not sent to the terminal:
    // the command can't redraw or disguise what's on screen.
    final shownCommand = visibleCommand(command.trim())
        .replaceAll('\t', '  ')
        .replaceAll('\n', '\r\n  ');
    // A rule across the terminal above and below what the assistant ran,
    // so it reads apart from the user's own commands:
    //   ── AI ───────────────────────────
    //   $ df -h
    //   (output)
    //   ── ✓ exit 0 · 0.3s ──────────────
    final width = (terminal.viewWidth - 1).clamp(20, 120);
    String rule(String label) {
      final head = '── $label ';
      return head + '─' * (width - head.length).clamp(3, width);
    }

    terminal.write(
      '\r\n\x1b[35m${rule(label)}\x1b[0m\r\n'
      '\x1b[1m\$ $shownCommand\x1b[0m\r\n',
    );
    final watch = Stopwatch()..start();
    try {
      final r = await exec(
        command,
        timeout: timeout,
        cancel: cancel,
        onStdout: (t) => show(t),
        onStderr: (t) => show(t, color: '\x1b[31m'),
      );
      if (!atLineStart) terminal.write('\r\n');
      final secs = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      final ok = r.exitCode == 0;
      final note = [
        if (r.timedOut) 'killed after ${timeout.inSeconds}s',
        if (r.truncated) 'output cut',
      ].join(', ');
      final status =
          '${ok ? '✓' : '✗'} exit ${r.exitCode ?? '?'} · ${secs}s'
          '${note.isEmpty ? '' : ' · $note'}';
      terminal.write(
        '${ok ? '\x1b[32m' : '\x1b[31m'}${rule(status)}\x1b[0m\r\n',
      );
      return r;
    } catch (e) {
      if (!atLineStart) terminal.write('\r\n');
      terminal.write('\x1b[31m${rule('✗ $e')}\x1b[0m\r\n');
      rethrow;
    } finally {
      // Put the prompt line back, cursor where it was.
      terminal.write(promptLine);
      if (cursorX < promptLine.length) {
        terminal.write(cursorX == 0 ? '\r' : '\r\x1b[${cursorX}C');
      }
    }
  }

  void close() {
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectAttempt = 0;
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
    String? pem = secrets.privateKey;
    String? passphrase = secrets.passphrase;
    final keyId = host.keyId;
    if (keyId != null) {
      final saved = await keys?.readSecrets(keyId);
      pem = saved?.privateKey;
      passphrase = saved?.passphrase;
      if (pem == null || pem.trim().isEmpty) {
        throw _ConnectError(currentL10n.keyDeletedError);
      }
    }
    if (pem == null || pem.trim().isEmpty) {
      throw _ConnectError(currentL10n.noKeyError);
    }
    if (SSHKeyPair.isEncryptedPem(pem) && (passphrase ?? '').isEmpty) {
      passphrase = await prompts.askSecret(
        title: currentL10n.enterKeyPassphrase,
        message: currentL10n.keyIsEncrypted(host.displayName),
      );
      if (passphrase == null) throw _ConnectError(currentL10n.loginCancelled);
    }
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  Future<String?> _resolvePassword(HostSecrets secrets) async {
    final saved = secrets.password;
    if (saved != null && saved.isNotEmpty) return saved;
    return prompts.askSecret(
      title: currentL10n.enterPassword,
      message: currentL10n.loginTo(host.target),
    );
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
          title: request.name.isNotEmpty
              ? request.name
              : currentL10n.serverVerification,
          message: p.promptText.trim(),
        );
      }
      if (answer == null) return null;
      answers.add(answer);
    }
    return answers;
  }

  void _onRemoteClosed(int gen, SSHSession shell) {
    if (gen != _generation || _disposed) return;
    // `exit` (or the shell ending) reports an exit status; a dropped
    // connection doesn't.
    final dropped = shell.exitCode == null && shell.exitSignal == null;
    log.info(
      'ssh',
      'Connection to ${host.target} ${dropped ? 'dropped' : 'closed'}',
    );
    _teardown();
    terminal.write(
      '\r\n\x1b[2m${currentL10n.connectionClosedMarker}\x1b[0m\r\n',
    );
    _setStatus(SessionStatus.closed);
    if (dropped) _scheduleReconnect();
  }

  /// Test hook: as if the connection dropped (no exit status).
  @visibleForTesting
  void debugConnectionDropped() {
    _teardown();
    _setStatus(SessionStatus.closed);
    _scheduleReconnect();
  }

  static bool _worthRetrying(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is SSHSocketError ||
      (e is SSHError &&
          e is! SSHAuthAbortError &&
          e is! SSHAuthFailError &&
          e is! SSHHostkeyError &&
          e is! SSHKeyDecryptError &&
          e is! SSHKeyDecodeError) ||
      e is HandshakeException;

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
    _fs = null;
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

class _FnSink implements Sink<String> {
  _FnSink(this.f);
  final void Function(String) f;

  @override
  void add(String data) => f(data);

  @override
  void close() {}
}

/// Automatic reconnect settings: on/off, how many tries, how long between.
typedef ReconnectPolicy = ({bool enabled, int attempts, Duration delay});

/// Environment variable set on each tab's shell, valued with the session
/// id, so the shell process can be found on the server.
const shellMarkerVar = 'LC_UESSH_SESSION';

/// Prints the working folder of the newest shell process carrying
/// [shellMarkerVar]=[id] (the one the user is typing into, also inside
/// a nested shell).
String shellCwdScript(String id) =>
    'best=; bt=0; '
    'for p in /proc/[0-9]*; do '
    "grep -qsxz '$shellMarkerVar=$id' \"\$p/environ\" 2>/dev/null || continue; "
    'case \$(cat \$p/comm 2>/dev/null) in '
    'bash|sh|zsh|fish|dash|ksh|mksh|tcsh|csh|ash|busybox) ;; *) continue;; esac; '
    "t=\$(cut -d' ' -f22 \$p/stat 2>/dev/null); "
    '[ "\${t:-0}" -ge "\$bt" ] && { bt=\$t; best=\$p; }; '
    'done; '
    '[ -n "\$best" ] && readlink "\$best/cwd"';

/// Like [shellCwdScript], for shells without the marker: the login shell
/// (owned by this user, parent sshd) that started closest to [startedAt]
/// (server epoch seconds; now if null), then the newest shell on its
/// terminal (a nested shell), and print that one's folder.
String shellCwdByStartScript(int? startedAt) =>
    r'''
T=__T__; hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
bt=$(awk '/^btime/{print $2}' /proc/stat)
shells='bash sh zsh fish dash ksh mksh tcsh csh ash'
isshell() { for s in $shells; do [ "$1" = "$s" ] && return 0; done; return 1; }
best=; bd=; tty=
for p in /proc/[0-9]*; do
  [ -O "$p" ] || continue
  isshell "$(cat "$p/comm" 2>/dev/null)" || continue
  set -- $(sed 's/^.*) //' "$p/stat" 2>/dev/null)
  [ "${5:-0}" = 0 ] && continue
  case "$(cat "/proc/$2/comm" 2>/dev/null)" in sshd*) ;; *) continue;; esac
  st=$(( bt + ${20} / hz )); d=$(( st > T ? st - T : T - st ))
  if [ -z "$bd" ] || [ "$d" -lt "$bd" ]; then bd=$d; best=$p; tty=$5; fi
done
[ -n "$best" ] || exit 0
nb=$best; ns=0
for p in /proc/[0-9]*; do
  [ -O "$p" ] || continue
  isshell "$(cat "$p/comm" 2>/dev/null)" || continue
  set -- $(sed 's/^.*) //' "$p/stat" 2>/dev/null)
  [ "$5" = "$tty" ] || continue
  if [ "${20}" -ge "$ns" ]; then ns=${20}; nb=$p; fi
done
readlink "$nb/cwd"
'''
        .replaceAll('__T__', startedAt?.toString() ?? r'$(date +%s)');

/// Output of [TerminalSession.exec].
class CommandResult {
  const CommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.truncated = false,
    this.timedOut = false,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;
  final bool truncated;
  final bool timedOut;
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
    return currentL10n.cannotConnect('${host.address}:${host.port}', reason);
  }
  if (e is TimeoutException) {
    return currentL10n.connectTimeout('${host.address}:${host.port}');
  }
  if (e is SSHAuthAbortError) return currentL10n.loginCancelled;
  if (e is SSHAuthFailError) return currentL10n.authFailed;
  if (e is SSHHostkeyError) return currentL10n.hostKeyRejected;
  if (e is SSHKeyDecryptError) return currentL10n.keyWrongPassphrase;
  if (e is SSHKeyDecodeError) return currentL10n.keyFormatShort;
  if (e is SSHError) return currentL10n.sshError('$e');
  return currentL10n.connectFailed('$e');
}
