import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/app_log.dart';
import '../ai/ai_chat.dart' show formatResult, terminalTail;
import '../ai/command_safety.dart' show isReadOnlyCommand;
import '../hosts/host.dart';
import '../settings/app_settings.dart' show McpApprovalMode;
import '../terminal/terminal_session.dart';

/// Result of calling one MCP tool.
class McpToolResult {
  const McpToolResult({required this.text, this.isError = false});

  final String text;
  final bool isError;

  Map<String, Object?> toJson() => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    if (isError) 'isError': true,
  };
}

/// Information passed to the user-facing approval prompt when an MCP client
/// asks to run a command, read terminal output, or open a host.
sealed class McpApprovalRequest {
  const McpApprovalRequest();
}

class McpCommandApproval extends McpApprovalRequest {
  const McpCommandApproval({
    required this.command,
    required this.hostLabel,
    required this.readOnly,
    this.purpose = '',
  });

  final String command;
  final String hostLabel;
  final bool readOnly;
  final String purpose;
}

class McpReadTerminalApproval extends McpApprovalRequest {
  const McpReadTerminalApproval({required this.hostLabel, required this.lines});

  final String hostLabel;
  final int lines;
}

class McpOpenSessionApproval extends McpApprovalRequest {
  const McpOpenSessionApproval({required this.hostLabel});

  final String hostLabel;
}

typedef McpApprovalCallback = Future<bool> Function(McpApprovalRequest request);

/// Bridge between the MCP protocol layer and uessh's sessions / hosts state.
abstract class McpBackend {
  bool get vaultUnlocked;
  McpApprovalMode get approvalMode;

  List<TerminalSession> get sessions;
  TerminalSession? get activeSession;
  TerminalSession? sessionById(String id);

  Future<List<Host>> listHosts();
  TerminalSession openHost(Host host);
  TerminalSession openLocal();

  Future<bool> requestApproval(McpApprovalRequest request);
}

/// JSON Schema definitions returned by `tools/list`.
final List<Map<String, Object?>> mcpToolDefinitions = [
  {
    'name': 'list_sessions',
    'description':
        'List all currently open terminal sessions in uessh (both SSH '
        'connections and local terminals), including their session_id, target '
        'host, connection status, and whether they are currently active.',
    'inputSchema': {
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
    'annotations': {
      'title': 'List terminal sessions',
      'readOnlyHint': true,
      'destructiveHint': false,
      'openWorldHint': false,
    },
  },
  {
    'name': 'list_hosts',
    'description':
        'List saved SSH hosts in uessh (non-sensitive metadata only: id, '
        'label, address, port, username, group). Never returns passwords or '
        'private keys.',
    'inputSchema': {
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
    'annotations': {
      'title': 'List saved hosts',
      'readOnlyHint': true,
      'destructiveHint': false,
      'openWorldHint': false,
    },
  },
  {
    'name': 'open_session',
    'description':
        'Open a new terminal tab for a saved SSH host (by host_id or label) '
        'or for a local shell (host_id: "local"), wait for it to connect, and '
        'return its session_id.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'host_id': {
          'type': 'string',
          'description':
              'Saved host ID from list_hosts, or "local" for a local terminal.',
        },
        'label': {
          'type': 'string',
          'description':
              'Saved host label or address (used if host_id is omitted).',
        },
        'reuse_existing': {
          'type': 'boolean',
          'description':
              'If true (default), return an already-connected session for that '
              'host instead of opening a duplicate tab.',
        },
        'timeout_seconds': {
          'type': 'integer',
          'description': 'Seconds to wait for connection (default 15, max 60).',
        },
      },
      'additionalProperties': false,
    },
    'annotations': {
      'title': 'Open terminal session',
      'readOnlyHint': false,
      'destructiveHint': false,
      'openWorldHint': true,
    },
  },
  {
    'name': 'run_command',
    'description':
        'Execute a shell command on a connected uessh terminal session and '
        'return its exit code, stdout, and stderr. The command and its live '
        'output are displayed inside the uessh terminal window. Modifying or '
        'sensitive commands require user approval in uessh.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'Shell command to execute.',
        },
        'session_id': {
          'type': 'string',
          'description':
              'Target session_id from list_sessions. Defaults to the currently '
              'active terminal session.',
        },
        'purpose': {
          'type': 'string',
          'description':
              'Short human-readable explanation of why this command is run '
              '(shown in the approval dialog when confirmation is needed).',
        },
        'timeout_seconds': {
          'type': 'integer',
          'description':
              'Command timeout in seconds (default 60, range 5–300).',
        },
      },
      'required': ['command'],
      'additionalProperties': false,
    },
    'annotations': {
      'title': 'Run shell command',
      'readOnlyHint': false,
      'destructiveHint': true,
      'openWorldHint': true,
    },
  },
  {
    'name': 'read_terminal',
    'description':
        'Read the most recent lines currently shown in a uessh terminal '
        'session (including recent scrollback).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'session_id': {
          'type': 'string',
          'description':
              'Target session_id from list_sessions. Defaults to the currently '
              'active terminal session.',
        },
        'lines': {
          'type': 'integer',
          'description': 'Number of lines to read (default 80, range 1–500).',
        },
      },
      'additionalProperties': false,
    },
    'annotations': {
      'title': 'Read terminal output',
      'readOnlyHint': true,
      'destructiveHint': false,
      'openWorldHint': false,
    },
  },
];

/// Executes MCP tool calls against [backend] while enforcing vault lock state,
/// command safety classification, user approvals, and terminal visibility.
class McpToolExecutor {
  McpToolExecutor(this.backend);

  final McpBackend backend;

  Future<McpToolResult> call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    if (!backend.vaultUnlocked) {
      return const McpToolResult(
        text: 'uessh vault is locked. Unlock uessh first.',
        isError: true,
      );
    }

    switch (name) {
      case 'list_sessions':
        return _listSessions();
      case 'list_hosts':
        return _listHosts();
      case 'open_session':
        return _openSession(arguments);
      case 'run_command':
        return _runCommand(arguments);
      case 'read_terminal':
        return _readTerminal(arguments);
      default:
        return McpToolResult(text: 'Unknown tool "$name".', isError: true);
    }
  }

  McpToolResult _listSessions() {
    final activeId = backend.activeSession?.id;
    final items = [
      for (final s in backend.sessions)
        {
          'session_id': s.id,
          'label': s.host.displayName,
          'host_id': s.host.id,
          'target': s.isLocal ? 'local' : s.host.target,
          'status': s.status.name,
          'is_local': s.isLocal,
          'is_active': s.id == activeId,
          if (s.title != null && s.title!.isNotEmpty) 'title': s.title,
        },
    ];
    return McpToolResult(
      text: const JsonEncoder.withIndent('  ').convert({'sessions': items}),
    );
  }

  Future<McpToolResult> _listHosts() async {
    final hosts = await backend.listHosts();
    final items = [
      for (final h in hosts)
        {
          'host_id': h.id,
          'label': h.displayName,
          'address': h.address,
          'port': h.port,
          'username': h.username,
          'auth_method': h.authMethod.name,
          if (h.groupId != null && h.groupId!.isNotEmpty) 'group_id': h.groupId,
        },
    ];
    return McpToolResult(
      text: const JsonEncoder.withIndent('  ').convert({'hosts': items}),
    );
  }

  Future<McpToolResult> _openSession(Map<String, Object?> args) async {
    final hostId = args['host_id'] is String
        ? (args['host_id'] as String).trim()
        : null;
    final label = args['label'] is String
        ? (args['label'] as String).trim()
        : null;
    final reuseExisting = args['reuse_existing'] is bool
        ? args['reuse_existing'] as bool
        : true;
    final timeoutSecs = ((args['timeout_seconds'] as num?)?.toInt() ?? 15)
        .clamp(3, 60);

    final isLocalRequest = hostId == 'local' || hostId == localHostId;
    Host? targetHost;
    if (!isLocalRequest) {
      if ((hostId == null || hostId.isEmpty) &&
          (label == null || label.isEmpty)) {
        return const McpToolResult(
          text: 'Provide "host_id" (or "local") or "label".',
          isError: true,
        );
      }
      final hosts = await backend.listHosts();
      for (final h in hosts) {
        if (hostId != null && hostId.isNotEmpty && h.id == hostId) {
          targetHost = h;
          break;
        }
        if (label != null &&
            label.isNotEmpty &&
            (h.displayName == label || h.address == label)) {
          targetHost = h;
          break;
        }
      }
      if (targetHost == null) {
        return McpToolResult(
          text: 'Host not found: ${hostId ?? label}',
          isError: true,
        );
      }
    }

    if (reuseExisting) {
      for (final existing in backend.sessions) {
        final match = isLocalRequest
            ? existing.isLocal
            : (!existing.isLocal && existing.host.id == targetHost!.id);
        if (match && existing.status == SessionStatus.connected) {
          return McpToolResult(
            text: const JsonEncoder.withIndent('  ').convert({
              'session_id': existing.id,
              'label': existing.host.displayName,
              'target': existing.isLocal ? 'local' : existing.host.target,
              'status': existing.status.name,
              'reused': true,
            }),
          );
        }
      }
    }

    final display = isLocalRequest
        ? 'Local terminal'
        : '${targetHost!.displayName} (${targetHost.target})';
    if (backend.approvalMode == McpApprovalMode.askAll) {
      final ok = await backend.requestApproval(
        McpOpenSessionApproval(hostLabel: display),
      );
      if (!ok) {
        return const McpToolResult(
          text: 'The user declined to open this session.',
          isError: true,
        );
      }
    }

    final session = isLocalRequest
        ? backend.openLocal()
        : backend.openHost(targetHost!);

    // Wait for the session to connect or fail.
    if (session.status == SessionStatus.connecting) {
      final settled = Completer<void>();
      void listener() {
        if (session.status != SessionStatus.connecting &&
            !settled.isCompleted) {
          settled.complete();
        }
      }

      session.addListener(listener);
      try {
        await settled.future.timeout(
          Duration(seconds: timeoutSecs),
          onTimeout: () {},
        );
      } finally {
        session.removeListener(listener);
      }
    }

    final failed = session.status == SessionStatus.failed;
    return McpToolResult(
      isError: failed,
      text: const JsonEncoder.withIndent('  ').convert({
        'session_id': session.id,
        'label': session.host.displayName,
        'target': session.isLocal ? 'local' : session.host.target,
        'status': session.status.name,
        if (session.error != null) 'error': session.error,
        'reused': false,
      }),
    );
  }

  TerminalSession? _resolveSession(Map<String, Object?> args) {
    final sessionId = args['session_id'];
    if (sessionId is String && sessionId.trim().isNotEmpty) {
      return backend.sessionById(sessionId.trim());
    }
    return backend.activeSession;
  }

  Future<McpToolResult> _runCommand(Map<String, Object?> args) async {
    final command = args['command'];
    if (command is! String || command.trim().isEmpty) {
      return const McpToolResult(text: 'Missing "command".', isError: true);
    }
    final session = _resolveSession(args);
    if (session == null) {
      return const McpToolResult(
        text:
            'No matching terminal session is open. Use list_sessions or '
            'open_session first.',
        isError: true,
      );
    }
    if (session.status != SessionStatus.connected) {
      return McpToolResult(
        text:
            'Session "${session.id}" is not connected (status: '
            '${session.status.name}).',
        isError: true,
      );
    }

    // Read-only classification knows POSIX shells; PowerShell on Windows
    // always asks under readOnlyAuto.
    final readOnly =
        !(session.isLocal && Platform.isWindows) && isReadOnlyCommand(command);
    final purpose = args['purpose'] is String ? args['purpose'] as String : '';
    final timeoutSecs = ((args['timeout_seconds'] as num?)?.toInt() ?? 60)
        .clamp(5, 300);

    final ask = switch (backend.approvalMode) {
      McpApprovalMode.allowAll => false,
      McpApprovalMode.askAll => true,
      McpApprovalMode.readOnlyAuto => !readOnly,
    };

    if (ask) {
      final hostLabel = session.isLocal
          ? session.host.displayName
          : '${session.host.displayName} (${session.host.target})';
      final ok = await backend.requestApproval(
        McpCommandApproval(
          command: command,
          hostLabel: hostLabel,
          readOnly: readOnly,
          purpose: purpose,
        ),
      );
      if (!ok) {
        return const McpToolResult(
          text: 'The user declined to run this command.',
          isError: true,
        );
      }
    }

    if (session.status != SessionStatus.connected) {
      return const McpToolResult(
        text: 'Not connected to the server; the command did not run.',
        isError: true,
      );
    }

    // Log only the program name and length: arguments may hold secrets.
    log.info(
      'mcp',
      'Running command: '
          '${command.trim().split(RegExp(r'\s+')).first} '
          '(${command.length} chars) on ${session.id}',
    );

    try {
      // Displayed live inside the terminal with the UESSH MCP header box.
      final result = await session.execShown(
        command,
        label: 'MCP',
        timeout: Duration(seconds: timeoutSecs),
      );
      return McpToolResult(text: formatResult(result));
    } catch (e) {
      return McpToolResult(
        text: 'Could not run the command: $e',
        isError: true,
      );
    }
  }

  Future<McpToolResult> _readTerminal(Map<String, Object?> args) async {
    final session = _resolveSession(args);
    if (session == null) {
      return const McpToolResult(
        text:
            'No matching terminal session is open. Use list_sessions or '
            'open_session first.',
        isError: true,
      );
    }
    final lines = ((args['lines'] as num?)?.toInt() ?? 80).clamp(1, 500);
    if (backend.approvalMode == McpApprovalMode.askAll) {
      final hostLabel = session.isLocal
          ? session.host.displayName
          : '${session.host.displayName} (${session.host.target})';
      final ok = await backend.requestApproval(
        McpReadTerminalApproval(hostLabel: hostLabel, lines: lines),
      );
      if (!ok) {
        return const McpToolResult(
          text: 'The user declined to share the terminal.',
          isError: true,
        );
      }
    }
    final tail = terminalTail(session, lines: lines);
    return McpToolResult(text: tail.isEmpty ? '(the terminal is empty)' : tail);
  }
}
