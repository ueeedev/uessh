import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_providers.dart';
import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../ai/command_safety.dart' show hasHiddenCharacters, visibleCommand;
import 'mcp_tools.dart';

/// Serializes MCP approval prompts so concurrent tool calls never stack
/// overlapping dialogs.
Future<void> _approvalQueue = Future<void>.value();

/// Prompts the user to approve or deny an external MCP tool request.
/// Returns `false` if no navigator is available or if the dialog is dismissed.
Future<bool> showMcpApprovalDialog(McpApprovalRequest request) {
  final result = Completer<bool>();
  _approvalQueue = _approvalQueue.then((_) async {
    try {
      final ok = await _showOne(request);
      result.complete(ok);
    } catch (_) {
      result.complete(false);
    }
  });
  return result.future;
}

Future<bool> _showOne(McpApprovalRequest request) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _McpApprovalDialog(request: request),
  );
  return answer ?? false;
}

class _McpApprovalDialog extends StatelessWidget {
  const _McpApprovalDialog({required this.request});

  final McpApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String title;
    final List<Widget> body;
    final bool destructive;

    switch (request) {
      case McpCommandApproval(
        :final command,
        :final hostLabel,
        :final readOnly,
        :final purpose,
      ):
        title = l.mcpApproveTitle;
        destructive = !readOnly;
        final hidden = hasHiddenCharacters(command);
        body = [
          Text(
            l.aiToolOnHost(hostLabel),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (purpose.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.mcpApprovePurpose(purpose.trim()),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              visibleCommand(command),
              style: TextStyle(
                fontFamily: monoFontFamily,
                fontFamilyFallback: monoFontFallback,
                fontSize: 13,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (hidden) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.aiToolHiddenChars,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ];
      case McpReadTerminalApproval(:final hostLabel, :final lines):
        title = l.mcpApproveReadTitle;
        destructive = false;
        body = [
          Text(
            l.aiToolOnHost(hostLabel),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(l.mcpApproveReadBody(lines), style: theme.textTheme.bodyMedium),
        ];
      case McpOpenSessionApproval(:final hostLabel):
        title = l.mcpApproveOpenTitle;
        destructive = false;
        body = [
          Text(
            l.mcpApproveOpenBody(hostLabel),
            style: theme.textTheme.bodyMedium,
          ),
        ];
    }

    return AlertDialog(
      key: const ValueKey('mcp-approval-dialog'),
      icon: Icon(
        destructive ? Icons.warning_amber_rounded : Icons.hub_outlined,
        color: destructive ? scheme.error : scheme.primary,
      ),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: body,
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('mcp-approve-deny'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.mcpApproveDeny),
        ),
        FilledButton(
          key: const ValueKey('mcp-approve-allow'),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.mcpApproveAllow),
        ),
      ],
    );
  }
}
