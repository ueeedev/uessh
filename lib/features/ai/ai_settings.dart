import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/side_sheet.dart';
import 'ai_chat.dart';
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_history.dart';

IconData _vendorIcon(AiVendor v) => switch (v) {
  AiVendor.anthropic => Icons.auto_awesome,
  AiVendor.openai => Icons.chat_bubble_outline,
  AiVendor.deepseek => Icons.water,
  AiVendor.gemini => Icons.diamond_outlined,
  AiVendor.grok => Icons.bolt,
  AiVendor.custom => Icons.hub_outlined,
};

/// Settings card listing AI providers; each opens [AiProviderSheet].
class AiSettingsCard extends ConsumerWidget {
  const AiSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final config = ref.watch(aiConfigProvider).value;
    if (config == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final added = [
      for (final p in config.providers)
        if (config.configured.contains(p.id)) p,
    ];
    return Card(
      child: Column(
        children: [
          // Only providers that were added; more via the menu below.
          if (added.isEmpty)
            ListTile(
              key: const ValueKey('ai-no-providers'),
              leading: Icon(
                Icons.key_off_outlined,
                color: theme.colorScheme.outline,
              ),
              title: Text(l.aiNoProviders),
              subtitle: Text(l.aiNoProvidersHint),
            ),
          for (final p in added)
            ListTile(
              key: ValueKey('ai-provider-tile-${p.id}'),
              leading: Icon(_vendorIcon(p.vendor)),
              title: Text(p.displayName),
              subtitle: Text(
                '${l.aiProviderConfigured} · ${p.effectiveBaseUrl}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showSideSheet<void>(
                context,
                builder: (_) => AiProviderSheet(provider: p),
              ),
            ),
          _AddProviderTile(config: config),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: Text(l.aiToolMode),
            subtitle: Text(l.aiToolModeSubtitle),
            trailing: AppDropdown<AiToolMode>(
              key: const ValueKey('ai-tool-mode'),
              value: config.toolMode,
              width: 240,
              entries: [
                AppDropdownEntry(
                  value: AiToolMode.autoReadOnly,
                  label: l.aiToolModeAuto,
                ),
                AppDropdownEntry(
                  value: AiToolMode.askAll,
                  label: l.aiToolModeAsk,
                ),
                AppDropdownEntry(value: AiToolMode.off, label: l.aiToolModeOff),
                AppDropdownEntry(
                  value: AiToolMode.allowAll,
                  label: l.aiToolModeAll,
                  icon: Icons.warning_amber_rounded,
                  color: theme.colorScheme.error,
                ),
              ],
              onChanged: (m) async {
                if (m == AiToolMode.allowAll &&
                    !await _confirmAllowAll(context)) {
                  return;
                }
                await ref.read(aiConfigProvider.notifier).setToolMode(m);
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l.aiClearHistory),
            subtitle: Text(l.aiClearHistorySubtitle),
            trailing: TextButton(
              key: const ValueKey('ai-clear-history'),
              onPressed: () => _confirmClearHistory(context, ref),
              child: Text(l.aiClear),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.aiKeyStored,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_sweep_outlined),
      title: Text(l.aiClearHistoryTitle),
      content: Text(l.aiClearHistoryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('ai-clear-history-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.aiClear),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(aiHistoryProvider.notifier).clear();
}

/// Asks before letting the assistant run every command unasked.
Future<bool> _confirmAllowAll(BuildContext context) async {
  final l = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(l.aiAllowAllTitle),
      content: Text(l.aiAllowAllBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('ai-allow-all-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.aiAllowAllConfirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "Add AI provider": a menu of the built-in providers (ones already
/// added are ticked and disabled) and a custom one; picking one opens its
/// editor.
class _AddProviderTile extends StatelessWidget {
  const _AddProviderTile({required this.config});

  final AiConfig config;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    void edit(AiProvider p) => showSideSheet<void>(
      context,
      builder: (_) => AiProviderSheet(provider: p),
    );
    return MenuAnchor(
      alignmentOffset: const Offset(56, 0),
      menuChildren: [
        for (final v in AiVendor.builtIn)
          MenuItemButton(
            key: ValueKey('ai-add-${v.name}'),
            leadingIcon: Icon(_vendorIcon(v), size: 20),
            trailingIcon: config.configured.contains(v.name)
                ? Text(
                    l.aiAlreadyAdded,
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  )
                : null,
            onPressed: config.configured.contains(v.name)
                ? null
                : () => edit(config.byId(v.name) ?? AiProvider.builtIn(v)),
            child: Text(v.label),
          ),
        const Divider(height: 8),
        MenuItemButton(
          key: const ValueKey('ai-add-custom'),
          leadingIcon: Icon(_vendorIcon(AiVendor.custom), size: 20),
          onPressed: () => edit(AiProvider.newCustom()),
          child: Text('${l.aiCustomProvider}…'),
        ),
      ],
      builder: (context, controller, _) => ListTile(
        key: const ValueKey('ai-add-provider'),
        leading: Icon(Icons.add, color: scheme.primary),
        title: Text(l.aiAddProvider, style: TextStyle(color: scheme.primary)),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Edit one provider: API key, base URL, and for custom providers name,
/// API format and extra model ids. "Test connection" lists its models.
class AiProviderSheet extends ConsumerStatefulWidget {
  const AiProviderSheet({super.key, required this.provider});

  final AiProvider provider;

  @override
  ConsumerState<AiProviderSheet> createState() => _AiProviderSheetState();
}

class _AiProviderSheetState extends ConsumerState<AiProviderSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.provider.name);
  late final _baseUrl = TextEditingController(text: widget.provider.baseUrl);
  late final _models = TextEditingController(
    text: widget.provider.extraModels.join(', '),
  );
  final _key = TextEditingController();
  late AiProtocol _protocol = widget.provider.effectiveProtocol;
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  AiProvider get _p => widget.provider;

  bool get _hasKey =>
      ref.read(aiConfigProvider).value?.configured.contains(_p.id) ?? false;

  bool get _exists => ref.read(aiConfigProvider).value?.byId(_p.id) != null;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _models.dispose();
    _key.dispose();
    super.dispose();
  }

  AiProvider _edited() => _p.copyWith(
    name: _name.text.trim(),
    baseUrl: _baseUrl.text.trim(),
    protocol: _p.isCustom ? _protocol : null,
    extraModels: [
      for (final m in _models.text.split(RegExp(r'[,，\s]+')))
        if (m.trim().isNotEmpty) m.trim(),
    ],
  );

  String? _apiKeyFor() {
    final typed = _key.text.trim();
    if (typed.isNotEmpty) return typed;
    return ref.read(aiConfigProvider.notifier).apiKey(_p.id);
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    final key = _apiKeyFor();
    if (key == null) {
      setState(() {
        _testOk = false;
        _testResult = context.l10n.aiKeyRequired;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final models = await ref
          .read(aiClientProvider)
          .listModels(_edited(), key);
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = context.l10n.aiTestOk(models.length);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = context.l10n.aiTestFailed('$e');
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final typed = _key.text.trim();
    if (typed.isEmpty && !_hasKey) {
      setState(() {
        _testOk = false;
        _testResult = context.l10n.aiKeyRequired;
      });
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(aiConfigProvider.notifier)
        .saveProvider(_edited(), apiKey: typed.isEmpty ? null : typed);
    ref.invalidate(aiModelsProvider(_p.id));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.aiRemoveTitle),
        content: Text(l.aiRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.aiRemoveProvider),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiConfigProvider.notifier).removeProvider(_p.id);
    ref.invalidate(aiModelsProvider(_p.id));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final hasKey = _hasKey;
    return SideSheet(
      title: _p.isCustom
          ? (_p.name.isEmpty ? l.aiCustomProvider : _p.name)
          : _p.vendor.label,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            if (_p.isCustom) ...[
              TextFormField(
                key: const ValueKey('ai-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.aiProviderName),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l.aiNameRequired : null,
              ),
              const SizedBox(height: 16),
              Text(l.aiProtocol, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<AiProtocol>(
                segments: [
                  ButtonSegment(
                    value: AiProtocol.openai,
                    label: Text(l.aiProtocolOpenai),
                  ),
                  ButtonSegment(
                    value: AiProtocol.anthropic,
                    label: Text(l.aiProtocolAnthropic),
                  ),
                ],
                selected: {_protocol},
                onSelectionChanged: (s) => setState(() => _protocol = s.first),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const ValueKey('ai-key'),
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.aiApiKey,
                helperText: hasKey ? l.aiApiKeyKeep : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (!_p.isCustom) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${l.aiGetKey}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Flexible(
                    child: SelectableText(
                      _p.vendor.keyUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.copy,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _p.vendor.keyUrl),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('ai-base-url'),
              controller: _baseUrl,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.aiBaseUrl,
                hintText: _p.isCustom ? 'https://example.com/v1' : null,
                helperText: _p.isCustom
                    ? null
                    : l.aiBaseUrlDefault(_p.vendor.baseUrl),
                helperMaxLines: 2,
              ),
              validator: (v) {
                final url = (v ?? '').trim();
                if (url.isEmpty) {
                  return _p.isCustom ? l.aiBaseUrlRequired : null;
                }
                final uri = Uri.tryParse(url);
                if (uri == null ||
                    !(uri.scheme == 'http' || uri.scheme == 'https') ||
                    uri.host.isEmpty) {
                  return l.aiBaseUrlInvalid;
                }
                if (!isAllowedApiUrl(uri)) return l.aiBaseUrlHttps;
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('ai-extra-models'),
              controller: _models,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.aiExtraModels,
                helperText: l.aiExtraModelsHelper,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('ai-test'),
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? l.aiTesting : l.aiTest),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _testOk ? Icons.check_circle_outline : Icons.error_outline,
                    size: 18,
                    color: _testOk
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _testResult!,
                      key: const ValueKey('ai-test-result'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      leadingActions: [
        if (hasKey || (_p.isCustom && _exists))
          TextButton.icon(
            key: const ValueKey('ai-remove'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _saving ? null : _remove,
            icon: const Icon(Icons.delete_outline),
            label: Text(l.aiRemoveProvider),
          ),
      ],
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('ai-save'),
          onPressed: _saving ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
