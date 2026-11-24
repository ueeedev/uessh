import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/app_providers.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import '../security/vault_controller.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import '../terminal/sessions_providers.dart';
import '../terminal/terminal_session.dart';
import 'mcp_approval_dialog.dart';
import 'mcp_server.dart';
import 'mcp_tools.dart';

/// Vault key storing the MCP bearer token.
const mcpTokenSecretKey = 'mcp:token';

class McpServerState {
  const McpServerState({
    this.running = false,
    this.port = AppSettings.defaultMcpPort,
    this.token,
    this.error,
  });

  final bool running;
  final int port;
  final String? token;
  final String? error;

  String get endpointUrl => 'http://127.0.0.1:$port/mcp';
  String get sseUrl => 'http://127.0.0.1:$port/sse';

  McpServerState copyWith({
    bool? running,
    int? port,
    Object? token = _keep,
    Object? error = _keep,
  }) => McpServerState(
    running: running ?? this.running,
    port: port ?? this.port,
    token: identical(token, _keep) ? this.token : token as String?,
    error: identical(error, _keep) ? this.error : error as String?,
  );

  static const _keep = Object();
}

/// Manages the lifecycle of UESSH's embedded local MCP server, keeping it in
/// sync with settings and vault lock state.
class McpController extends Notifier<McpServerState> {
  McpServer? _server;
  Future<void> _op = Future<void>.value();

  @override
  McpServerState build() {
    ref.onDispose(() {
      final s = _server;
      _server = null;
      if (s != null) unawaited(s.stop());
    });

    ref.listen(
      settingsProvider.select((s) => (s.mcpEnabled, s.mcpPort)),
      (_, _) => _enqueueSync(),
    );
    ref.listen(
      vaultControllerProvider.select((v) => v.locked),
      (_, _) => _enqueueSync(),
    );

    final settings = ref.read(settingsProvider);
    if (settings.mcpEnabled) {
      Future.microtask(_enqueueSync);
    }
    return McpServerState(port: settings.mcpPort);
  }

  void _enqueueSync() {
    _op = _op.then((_) => _sync());
  }

  Future<String?> _ensureToken() async {
    final vault = ref.read(vaultProvider);
    if (!vault.isUnlocked) return null;
    final store = ref.read(secretStoreProvider);
    var token = await store.read(mcpTokenSecretKey);
    if (token == null || token.isEmpty) {
      token = McpServer.generateToken();
      await store.write(mcpTokenSecretKey, token);
    }
    return token;
  }

  Future<void> _sync() async {
    if (!ref.mounted) return;
    final settings = ref.read(settingsProvider);
    final token = await _ensureToken();
    if (!ref.mounted) return;

    if (!settings.mcpEnabled) {
      await _stopServer();
      if (!ref.mounted) return;
      state = state.copyWith(
        running: false,
        port: settings.mcpPort,
        token: token,
        error: null,
      );
      return;
    }

    if (token == null) {
      // Vault is locked; wait until unlocked before starting.
      await _stopServer();
      if (!ref.mounted) return;
      state = state.copyWith(
        running: false,
        port: settings.mcpPort,
        token: null,
        error: null,
      );
      return;
    }

    final current = _server;
    if (current != null &&
        current.isRunning &&
        current.port == settings.mcpPort &&
        current.token == token) {
      state = state.copyWith(
        running: true,
        port: settings.mcpPort,
        token: token,
        error: null,
      );
      return;
    }

    await _stopServer();
    if (!ref.mounted) return;

    final server = McpServer(
      executor: McpToolExecutor(_RiverpodMcpBackend(ref)),
      token: token,
    );
    try {
      await server.start(settings.mcpPort);
      if (!ref.mounted) {
        await server.stop();
        return;
      }
      _server = server;
      state = McpServerState(
        running: true,
        port: server.port ?? settings.mcpPort,
        token: token,
      );
    } catch (e) {
      log.warn('mcp', 'Failed to start MCP server: $e');
      await server.stop();
      if (!ref.mounted) return;
      state = McpServerState(
        running: false,
        port: settings.mcpPort,
        token: token,
        error: '$e',
      );
    }
  }

  Future<void> _stopServer() async {
    final s = _server;
    _server = null;
    if (s != null) await s.stop();
  }

  /// Generates a new bearer token, saves it to the vault, and restarts the
  /// server if currently enabled.
  Future<String?> regenerateToken() async {
    final vault = ref.read(vaultProvider);
    if (!vault.isUnlocked) return null;
    final token = McpServer.generateToken();
    await ref.read(secretStoreProvider).write(mcpTokenSecretKey, token);
    if (!ref.mounted) return token;
    state = state.copyWith(token: token);
    _enqueueSync();
    await _op;
    return token;
  }
}

class _RiverpodMcpBackend implements McpBackend {
  _RiverpodMcpBackend(this._ref);

  final Ref _ref;

  @override
  bool get vaultUnlocked => _ref.read(vaultProvider).isUnlocked;

  @override
  McpApprovalMode get approvalMode =>
      _ref.read(settingsProvider).mcpApprovalMode;

  @override
  List<TerminalSession> get sessions => _ref.read(sessionsProvider).sessions;

  @override
  TerminalSession? get activeSession => _ref.read(sessionsProvider).active;

  @override
  TerminalSession? sessionById(String id) =>
      _ref.read(sessionsProvider).session(id);

  @override
  Future<List<Host>> listHosts() async {
    final state = _ref.read(hostsProvider);
    if (state.hasValue) return state.value!.hosts;
    final loaded = await _ref.read(hostRepositoryProvider).load();
    return loaded.hosts;
  }

  @override
  TerminalSession openHost(Host host) =>
      _ref.read(sessionsProvider.notifier).open(host);

  @override
  TerminalSession openLocal() =>
      _ref.read(sessionsProvider.notifier).openLocal();

  @override
  Future<bool> requestApproval(McpApprovalRequest request) =>
      showMcpApprovalDialog(request);
}

final mcpControllerProvider = NotifierProvider<McpController, McpServerState>(
  McpController.new,
);
