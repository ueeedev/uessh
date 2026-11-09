part of 'terminal_session.dart';

/// Host id of the local terminal (not a saved host).
const localHostId = 'uessh-local';

/// The pseudo host a local terminal tab runs on.
Host localHost() => Host(
  id: localHostId,
  label: currentL10n.localTerminal,
  address: 'localhost',
  port: 22,
  username:
      Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '',
  authMethod: AuthMethod.password,
);

/// A shell on this computer (zsh / bash on macOS, PowerShell on Windows)
/// in a pseudo terminal, shown like an SSH tab.
///
/// The extras that need a server connection (file browser, server info,
/// AI commands) aren't available here.
class LocalTerminalSession extends TerminalSession {
  LocalTerminalSession({
    required super.host,
    required super.repository,
    required super.knownHosts,
    required super.prompts,
  });

  Pty? _pty;

  @override
  bool get isLocal => true;

  /// The shell to start, and its arguments.
  static (String, List<String>) shellCommand() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final root = env['SystemRoot'] ?? r'C:\Windows';
      final ps = '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
      if (File(ps).existsSync()) return (ps, const ['-NoLogo']);
      return (env['ComSpec'] ?? 'cmd.exe', const []);
    }
    final shell = env['SHELL'];
    final exe = shell != null && File(shell).existsSync() ? shell : '/bin/zsh';
    // A login shell reads the user's profile, so PATH etc. are as in
    // Terminal (apps opened from Finder get a minimal PATH).
    return (exe, const ['-l']);
  }

  @override
  Future<void> connect({bool auto = false}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnectAttempt = 0;
    _teardown();
    _killPty();
    final gen = ++_generation;
    _setStatus(SessionStatus.connecting);
    try {
      final (exe, args) = shellCommand();
      final env = Platform.environment;
      final home = env['HOME'] ?? env['USERPROFILE'];
      final pty = Pty.start(
        exe,
        arguments: args,
        workingDirectory: home,
        environment: {
          ...env,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'TERM_PROGRAM': 'uessh',
          if (!env.containsKey('LANG') && !Platform.isWindows)
            'LANG': 'en_US.UTF-8',
        },
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );
      _pty = pty;
      _subs.add(
        pty.output
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen((data) {
              terminal.write(data);
              highlighter.afterOutput();
            }),
      );
      terminal.onOutput = (data) {
        highlighter.onInput(data);
        pty.write(utf8.encode(data));
        onUserInput?.call(data);
        if (data.contains('\r')) onCommandEntered?.call();
      };
      terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);
      connectedAt = DateTime.now();
      log.info('local', 'Started $exe');
      _setStatus(SessionStatus.connected);
      unawaited(pty.exitCode.then((code) => _onExit(gen, code)));
    } catch (e) {
      if (gen != _generation) return;
      _teardown();
      _killPty();
      error = currentL10n.localTerminalFailed('$e');
      log.warn('local', 'Could not start the shell: $e');
      terminal.write('\r\n\x1b[31m$error\x1b[0m\r\n');
      _setStatus(SessionStatus.failed);
    }
  }

  void _onExit(int gen, int code) {
    if (gen != _generation || _disposed) return;
    log.info('local', 'Shell exited ($code)');
    _teardown();
    _pty = null;
    terminal.write('\r\n\x1b[2m${currentL10n.localTerminalEnded}\x1b[0m\r\n');
    // A shell that ends was asked to (exit, Ctrl+D): no reconnect.
    _setStatus(SessionStatus.closed);
  }

  void _killPty() {
    _pty?.kill();
    _pty = null;
  }

  @override
  void sendInput(String data) {
    debugOnSend?.call(data);
    highlighter.onInput(data);
    _pty?.write(utf8.encode(data));
  }

  @override
  void close() {
    _killPty();
    super.close();
  }

  // --- Instead of the server: this computer ---

  final LocalFs _localFs = LocalFs();

  @override
  Future<RemoteFs> remoteFs() async {
    if (status != SessionStatus.connected) throw StateError('not connected');
    return _localFs;
  }

  /// The shell's current folder, as the file browser writes paths.
  /// macOS / Linux: asked from the system (lsof); Windows: unknown.
  @override
  Future<String?> shellCwd() async {
    final pty = _pty;
    if (pty == null || Platform.isWindows) return null;
    try {
      final r = await Process.run('lsof', [
        '-a',
        '-p',
        '${pty.pid}',
        '-d',
        'cwd',
        '-Fn',
      ]).timeout(const Duration(seconds: 3));
      for (final line in '${r.stdout}'.split('\n')) {
        if (line.startsWith('n/')) return line.substring(1);
      }
    } catch (_) {}
    return null;
  }

  /// [shellCwd], unless that folder was removed meanwhile.
  Future<String?> _existingCwd() async {
    final cwd = await shellCwd();
    return cwd != null && await Directory(cwd).exists() ? cwd : null;
  }

  @override
  String cdCommand(String folder) {
    if (!Platform.isWindows) return super.cdCommand(folder);
    final native = _localFs.toNative(folder).replaceAll("'", "''");
    return " Set-Location -LiteralPath '$native'\r";
  }

  @override
  String get statsCommand =>
      Platform.isWindows ? windowsStatsScript : macStatsScript;

  /// PATH as the user's login shell sets it (apps opened from Finder get a
  /// minimal one, without Homebrew etc.), looked up once.
  static Future<String?>? _loginPath;

  static Future<String?> _userPath() => _loginPath ??= () async {
    if (Platform.isWindows) return null;
    try {
      final (shell, _) = shellCommand();
      final r = await Process.run(shell, [
        '-l',
        '-c',
        r'printf "%s" "$PATH"',
      ]).timeout(const Duration(seconds: 5));
      final path = '${r.stdout}'.trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }();

  /// Runs [command] on this computer: `sh -c` (POSIX, like on servers) on
  /// macOS / Linux, PowerShell on Windows; in the shell's current folder.
  @override
  Future<CommandResult> exec(
    String command, {
    Duration timeout = const Duration(seconds: 60),
    int maxBytes = 64 * 1024,
    void Function(String text)? onStdout,
    void Function(String text)? onStderr,
    Future<void>? cancel,
  }) async {
    if (status != SessionStatus.connected) throw StateError('not connected');
    final env = {...Platform.environment};
    final path = await _userPath();
    if (path != null) env['PATH'] = path;
    final home = _localFs.toNative(await _localFs.home());
    final Process process;
    if (Platform.isWindows) {
      process = await Process.start(
        'powershell.exe',
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', command],
        workingDirectory: home,
        environment: env,
      );
    } else {
      process = await Process.start(
        '/bin/sh',
        ['-c', command],
        workingDirectory: await _existingCwd() ?? home,
        environment: env,
      );
    }
    // Nothing to type into it: commands waiting for input end at once.
    unawaited(process.stdin.close());

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

    ByteConversionSink? live(void Function(String)? f) => f == null
        ? null
        : const Utf8Decoder(allowMalformed: true)
              .startChunkedConversion(_FnSink(f));
    final liveOut = live(onStdout), liveErr = live(onStderr);
    final outDone = process.stdout.listen((c) {
      final before = out.length;
      collect(out, c);
      if (out.length > before) liveOut?.add(out.sublist(before));
    }).asFuture<void>();
    final errDone = process.stderr.listen((c) {
      final before = err.length;
      collect(err, c);
      if (err.length > before) liveErr?.add(err.sublist(before));
    }).asFuture<void>();
    // Stop button: end the command, not just the wait.
    cancel?.then((_) => process.kill());
    var timedOut = false;
    int? code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    }
    await Future.wait([outDone, errDone])
        .timeout(const Duration(seconds: 2), onTimeout: () => const []);
    liveOut?.close();
    liveErr?.close();
    return CommandResult(
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
      exitCode: code,
      truncated: truncated,
      timedOut: timedOut,
    );
  }

  @override
  Future<String?> runCommand(
    String command, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (status != SessionStatus.connected) return null;
    try {
      final r = await exec(command, timeout: timeout);
      return r.timedOut ? null : r.stdout;
    } catch (_) {
      return null;
    }
  }
}

/// This Mac's information, in the same `@@section` format as
/// [serverStatsCommand] (memory as /proc/meminfo lines, disk as a df line).
/// CPU is the processes' total share right now (`@@cpupct`).
const macStatsScript = r'''
echo @@hostname; scutil --get ComputerName 2>/dev/null || hostname
echo @@os; echo "$(sw_vers -productName) $(sw_vers -productVersion)"
echo @@kernel; uname -r
echo @@uptime; boot=$(sysctl -n kern.boottime | sed 's/^{ sec = \([0-9]*\).*/\1/'); echo $(( $(date +%s) - boot ))
echo @@load; sysctl -n vm.loadavg | tr -d '{}'
echo @@nproc; sysctl -n hw.ncpu
echo @@cpupct; ps -A -o %cpu= | awk -v n="$(sysctl -n hw.ncpu)" '{s+=$1} END {printf "%.1f\n", s/n}'
echo @@mem; echo "MemTotal: $(( $(sysctl -n hw.memsize) / 1024 )) kB"
vm_stat | awk -v ps="$(sysctl -n hw.pagesize)" '/Pages free|Pages inactive|Pages speculative|Pages purgeable/ {gsub(/\./,"",$NF); s+=$NF} END {printf "MemAvailable: %d kB\n", s*ps/1024}'
echo @@disk; df -kP /System/Volumes/Data 2>/dev/null | tail -n 1 || df -kP / | tail -n 1
echo @@end
''';

/// This Windows PC's information, in the same `@@section` format.
const windowsStatsScript = r'''
$os = Get-CimInstance Win32_OperatingSystem
'@@hostname'; $env:COMPUTERNAME
'@@os'; $os.Caption
'@@kernel'; $os.Version
'@@uptime'; [int]((Get-Date) - $os.LastBootUpTime).TotalSeconds
'@@nproc'; [Environment]::ProcessorCount
'@@cpupct'; (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
'@@mem'; "MemTotal: $($os.TotalVisibleMemorySize) kB"; "MemAvailable: $($os.FreePhysicalMemory) kB"
'@@disk'; $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"; "$($env:SystemDrive) $([long]($d.Size/1024)) $([long](($d.Size-$d.FreeSpace)/1024)) $([long]($d.FreeSpace/1024))"
'@@end'
''';
