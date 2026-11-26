import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/proxy_settings.dart';
import '../../core/proxy_transport.dart';
import '../../core/system_proxy.dart';
import '../../l10n/l10n.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/toasts.dart';
import 'settings_providers.dart';

/// Reads the OS system proxy for display in Settings (replaceable in tests).
final systemProxyInspectorProvider = Provider<SystemProxyConfig Function()>(
  (ref) => readOsSystemProxySync,
);

/// Settings card split cleanly into AI network proxy and SSH network proxy.
class ProxySettingsCard extends ConsumerStatefulWidget {
  const ProxySettingsCard({super.key});

  @override
  ConsumerState<ProxySettingsCard> createState() => _ProxySettingsCardState();
}

class _ProxySettingsCardState extends ConsumerState<ProxySettingsCard> {
  SystemProxyConfig _systemProxy = SystemProxyConfig.direct;

  @override
  void initState() {
    super.initState();
    _refreshSystemProxy();
  }

  void _refreshSystemProxy() {
    final cfg = ref.read(systemProxyInspectorProvider)();
    if (mounted) {
      setState(() => _systemProxy = cfg);
    } else {
      _systemProxy = cfg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);

    return Card(
      key: const ValueKey('proxy-settings-card'),
      child: Column(
        children: [
          _ProxyEntrySection(
            prefix: 'ai-proxy',
            icon: Icons.auto_awesome_outlined,
            title: l.aiProxyTitle,
            subtitle: l.aiProxySubtitle,
            settings: settings.aiProxy,
            vaultPasswordKey: aiProxyPasswordKey,
            systemProxySummary: _systemProxy.summary,
            onRefreshSystemProxy: _refreshSystemProxy,
            onSave: (next) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(aiProxy: next)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _ProxyEntrySection(
            prefix: 'ssh-proxy',
            icon: Icons.vpn_lock_outlined,
            title: l.sshProxyTitle,
            subtitle: l.sshProxySubtitle,
            settings: settings.sshProxy,
            vaultPasswordKey: sshProxyPasswordKey,
            systemProxySummary: _sshSystemSummary(_systemProxy),
            onRefreshSystemProxy: _refreshSystemProxy,
            onSave: (next) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(sshProxy: next)),
          ),
        ],
      ),
    );
  }

  static String? _sshSystemSummary(SystemProxyConfig cfg) {
    if (cfg.socksProxy != null) return 'socks5://${cfg.socksProxy}';
    return cfg.summary;
  }
}

class _ProxyEntrySection extends ConsumerStatefulWidget {
  const _ProxyEntrySection({
    required this.prefix,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.settings,
    required this.vaultPasswordKey,
    required this.systemProxySummary,
    required this.onRefreshSystemProxy,
    required this.onSave,
  });

  final String prefix;
  final IconData icon;
  final String title;
  final String subtitle;
  final ProxySettings settings;
  final String vaultPasswordKey;
  final String? systemProxySummary;
  final VoidCallback onRefreshSystemProxy;
  final ValueChanged<ProxySettings> onSave;

  @override
  ConsumerState<_ProxyEntrySection> createState() => _ProxyEntrySectionState();
}

class _ProxyEntrySectionState extends ConsumerState<_ProxyEntrySection> {
  final _formKey = GlobalKey<FormState>();
  late ProxyScheme _scheme = widget.settings.scheme;
  late final _host = TextEditingController(text: widget.settings.host);
  late final _port = TextEditingController(text: '${widget.settings.port}');
  late final _username = TextEditingController(text: widget.settings.username);
  final _password = TextEditingController();

  bool _testing = false;
  bool _saving = false;
  bool _obscurePassword = true;
  bool _hasSavedPassword = false;

  @override
  void initState() {
    super.initState();
    _hasSavedPassword = _readSavedPassword()?.isNotEmpty ?? false;
  }

  @override
  void didUpdateWidget(_ProxyEntrySection old) {
    super.didUpdateWidget(old);
    if (old.settings != widget.settings) {
      _scheme = widget.settings.scheme;
      if (_host.text != widget.settings.host) {
        _host.text = widget.settings.host;
      }
      final portStr = '${widget.settings.port}';
      if (_port.text != portStr) _port.text = portStr;
      if (_username.text != widget.settings.username) {
        _username.text = widget.settings.username;
      }
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _readSavedPassword() {
    try {
      return ref.read(vaultProvider).read(widget.vaultPasswordKey);
    } catch (_) {
      return null;
    }
  }

  void _setMode(ProxyMode mode) {
    if (mode == ProxyMode.system) {
      widget.onRefreshSystemProxy();
    }
    widget.onSave(widget.settings.copyWith(mode: mode));
  }

  ProxySettings _buildDraft() => ProxySettings(
    mode: ProxyMode.custom,
    scheme: _scheme,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? ProxySettings.defaultPort,
    username: _username.text.trim(),
  );

  Future<void> _saveCustom() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final draft = _buildDraft();
      final typedPass = _password.text;
      if (typedPass.isNotEmpty) {
        await ref.read(vaultProvider).write(widget.vaultPasswordKey, typedPass);
        _hasSavedPassword = true;
        _password.clear();
      } else if (draft.username.isEmpty && _hasSavedPassword) {
        // Clearing the username clears any orphaned proxy password too.
        await ref.read(vaultProvider).write(widget.vaultPasswordKey, null);
        _hasSavedPassword = false;
      }
      widget.onSave(draft);
      if (mounted) {
        showToast(context.l10n.proxySaved, kind: ToastKind.success);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testCustom() async {
    if (!_formKey.currentState!.validate()) return;
    final l = context.l10n;
    final draft = _buildDraft();
    final pass = _password.text.isNotEmpty
        ? _password.text
        : _readSavedPassword();
    setState(() => _testing = true);
    try {
      await testProxyReachability(proxy: draft, password: pass);
      if (mounted) {
        showToast(
          l.proxyTestOk(draft.displayEndpoint),
          kind: ToastKind.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(l.proxyTestFailed('$e'), kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = widget.settings.mode;

    final String statusLine;
    final Color statusColor;
    switch (mode) {
      case ProxyMode.system:
        final detected = widget.systemProxySummary;
        if (detected != null) {
          statusLine = l.proxySystemDetected(detected);
          statusColor = scheme.primary;
        } else {
          statusLine = l.proxySystemNone;
          statusColor = scheme.onSurfaceVariant;
        }
      case ProxyMode.direct:
        statusLine = l.proxyModeDirect;
        statusColor = scheme.onSurfaceVariant;
      case ProxyMode.custom:
        if (widget.settings.isCustomValid) {
          statusLine = widget.settings.displayEndpoint;
          statusColor = scheme.primary;
        } else {
          statusLine = l.proxyCustomNotSet;
          statusColor = scheme.error;
        }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(widget.icon),
          title: Text(widget.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      statusLine,
                      key: ValueKey('${widget.prefix}-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (mode == ProxyMode.system) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.onRefreshSystemProxy,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.refresh,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: SegmentedButton<ProxyMode>(
            key: ValueKey('${widget.prefix}-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ProxyMode.system,
                label: Text(l.proxyModeSystem),
              ),
              ButtonSegment(
                value: ProxyMode.direct,
                label: Text(l.proxyModeDirect),
              ),
              ButtonSegment(
                value: ProxyMode.custom,
                label: Text(l.proxyModeCustom),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (v) => _setMode(v.first),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: mode != ProxyMode.custom
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(56, 4, 16, 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Tooltip(
                                message: l.proxyScheme,
                                child: AppDropdown<ProxyScheme>(
                                  key: ValueKey('${widget.prefix}-scheme'),
                                  value: _scheme,
                                  onChanged: (v) => setState(() => _scheme = v),
                                  entries: const [
                                    AppDropdownEntry(
                                      value: ProxyScheme.http,
                                      label: 'HTTP',
                                    ),
                                    AppDropdownEntry(
                                      value: ProxyScheme.socks5,
                                      label: 'SOCKS5',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                key: ValueKey('${widget.prefix}-host'),
                                controller: _host,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: l.proxyHost,
                                  hintText: '127.0.0.1',
                                ),
                                validator: (v) => (v ?? '').trim().isEmpty
                                    ? l.proxyHostRequired
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                key: ValueKey('${widget.prefix}-port'),
                                controller: _port,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: l.proxyPort,
                                  hintText: '7890',
                                ),
                                validator: (v) {
                                  final n = int.tryParse((v ?? '').trim());
                                  if (n == null || n < 1 || n > 65535) {
                                    return l.proxyPortInvalid;
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('${widget.prefix}-user'),
                                controller: _username,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: l.proxyUsername,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('${widget.prefix}-pass'),
                                controller: _password,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: l.proxyPassword,
                                  hintText: _hasSavedPassword
                                      ? l.proxyPasswordKeepHint
                                      : null,
                                  suffixIcon: IconButton(
                                    iconSize: 18,
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              key: ValueKey('${widget.prefix}-test'),
                              onPressed: _testing || _saving
                                  ? null
                                  : _testCustom,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.network_check, size: 17),
                              label: Text(
                                _testing ? l.proxyTesting : l.proxyTest,
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              key: ValueKey('${widget.prefix}-save'),
                              onPressed: _saving ? null : _saveCustom,
                              child: Text(l.save),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
