import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/toasts.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import 'mcp_controller.dart';
import 'mcp_server.dart';

/// Settings card for configuring and monitoring UESSH's local MCP server.
class McpSettingsCard extends ConsumerStatefulWidget {
  const McpSettingsCard({super.key});

  @override
  ConsumerState<McpSettingsCard> createState() => _McpSettingsCardState();
}

class _McpSettingsCardState extends ConsumerState<McpSettingsCard> {
  bool _showToken = false;

  Future<void> _editPort(int currentPort) async {
    final l = context.l10n;
    final controller = TextEditingController(text: '$currentPort');
    String? errorText;
    final nextPort = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.mcpPort),
          content: TextField(
            key: const ValueKey('mcp-port-input'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              helperText: l.mcpPortSubtitle,
              errorText: errorText,
            ),
            onSubmitted: (_) {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null ||
                  parsed < AppSettings.minMcpPort ||
                  parsed > AppSettings.maxMcpPort) {
                setDialogState(() => errorText = l.mcpPortInvalid);
                return;
              }
              Navigator.of(ctx).pop(parsed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null ||
                    parsed < AppSettings.minMcpPort ||
                    parsed > AppSettings.maxMcpPort) {
                  setDialogState(() => errorText = l.mcpPortInvalid);
                  return;
                }
                Navigator.of(ctx).pop(parsed);
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (nextPort != null && nextPort != currentPort) {
      ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(mcpPort: nextPort));
    }
  }

  Future<void> _setApprovalMode(McpApprovalMode mode) async {
    if (mode == McpApprovalMode.allowAll) {
      final l = context.l10n;
      final scheme = Theme.of(context).colorScheme;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
          title: Text(l.mcpAllowAllTitle),
          content: Text(l.mcpAllowAllBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.mcpApproveAllow),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(mcpApprovalMode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final mcp = ref.watch(mcpControllerProvider);

    final String statusText;
    final Color statusColor;
    if (mcp.error != null) {
      statusText = l.mcpError(mcp.error!);
      statusColor = scheme.error;
    } else if (mcp.running) {
      statusText = l.mcpRunning(mcp.endpointUrl);
      statusColor = scheme.primary;
    } else {
      statusText = l.mcpStopped;
      statusColor = scheme.onSurfaceVariant;
    }

    final token = mcp.token;
    final maskedToken = token == null
        ? l.mcpTokenLocked
        : (_showToken ? token : '${token.substring(0, 6)}••••••••••••');

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('mcp-enable'),
            secondary: const Icon(Icons.hub_outlined),
            title: Text(l.mcpEnable),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.mcpEnableSubtitle),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  key: const ValueKey('mcp-status'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            value: settings.mcpEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(mcpEnabled: v)),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !settings.mcpEnabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.lan_outlined),
                        title: Text(l.mcpPort),
                        subtitle: Text(l.mcpPortSubtitle),
                        trailing: FilledButton.tonal(
                          key: const ValueKey('mcp-port-button'),
                          onPressed: () => _editPort(settings.mcpPort),
                          child: Text('${settings.mcpPort}'),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(l.mcpApprovalMode),
                        subtitle: Text(l.mcpApprovalModeSubtitle),
                        trailing: AppDropdown<McpApprovalMode>(
                          key: const ValueKey('mcp-approval-mode'),
                          width: 240,
                          value: settings.mcpApprovalMode,
                          onChanged: _setApprovalMode,
                          entries: [
                            AppDropdownEntry(
                              value: McpApprovalMode.readOnlyAuto,
                              label: l.mcpApprovalReadOnly,
                            ),
                            AppDropdownEntry(
                              value: McpApprovalMode.askAll,
                              label: l.mcpApprovalAskAll,
                            ),
                            AppDropdownEntry(
                              value: McpApprovalMode.allowAll,
                              label: l.mcpApprovalAllowAll,
                              icon: Icons.warning_amber_rounded,
                              color: scheme.error,
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(l.mcpEndpoint),
                        subtitle: SelectableText(
                          mcp.endpointUrl,
                          style: TextStyle(
                            fontFamily: monoFontFamily,
                            fontFamilyFallback: monoFontFallback,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: l.copy,
                          icon: const Icon(Icons.content_copy_outlined),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: mcp.endpointUrl),
                            );
                            showToast(
                              l.mcpEndpointCopied,
                              kind: ToastKind.success,
                            );
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.key_outlined),
                        title: Text(l.mcpToken),
                        subtitle: SelectableText(
                          maskedToken,
                          style: TextStyle(
                            fontFamily: monoFontFamily,
                            fontFamilyFallback: monoFontFallback,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: _showToken
                                  ? l.filesHideHidden
                                  : l.filesShowHidden,
                              icon: Icon(
                                _showToken
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: token == null
                                  ? null
                                  : () => setState(
                                      () => _showToken = !_showToken,
                                    ),
                            ),
                            IconButton(
                              key: const ValueKey('mcp-copy-token'),
                              tooltip: l.copy,
                              icon: const Icon(Icons.content_copy_outlined),
                              onPressed: token == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: token),
                                      );
                                      showToast(
                                        l.mcpTokenCopied,
                                        kind: ToastKind.success,
                                      );
                                    },
                            ),
                            IconButton(
                              key: const ValueKey('mcp-regenerate-token'),
                              tooltip: l.mcpRegenerateToken,
                              icon: const Icon(Icons.refresh),
                              onPressed: token == null
                                  ? null
                                  : () async {
                                      await ref
                                          .read(mcpControllerProvider.notifier)
                                          .regenerateToken();
                                      showToast(
                                        l.mcpTokenRegenerated,
                                        kind: ToastKind.success,
                                      );
                                    },
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('mcp-copy-config'),
                            icon: const Icon(Icons.code, size: 18),
                            label: Text(l.mcpCopyConfig),
                            onPressed: token == null
                                ? null
                                : () async {
                                    final json = McpServer.clientConfigJson(
                                      port: mcp.port,
                                      token: token,
                                    );
                                    await Clipboard.setData(
                                      ClipboardData(text: json),
                                    );
                                    showToast(
                                      l.mcpConfigCopied,
                                      kind: ToastKind.success,
                                    );
                                  },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
