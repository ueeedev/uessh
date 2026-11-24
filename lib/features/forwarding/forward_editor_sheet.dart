import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../shell/navigation.dart';
import '../../theme/terminal_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/side_sheet.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import 'forwarding_providers.dart';
import 'port_forward.dart';

/// Full localized label for [type], including the OpenSSH flag.
String forwardTypeLabel(AppLocalizations l, ForwardType type) => switch (type) {
  ForwardType.local => l.forwardTypeLocal,
  ForwardType.remote => l.forwardTypeRemote,
  ForwardType.dynamic => l.forwardTypeDynamic,
};

/// Compact badge label shown on cards.
String forwardTypeBadge(AppLocalizations l, ForwardType type) => switch (type) {
  ForwardType.local => l.forwardBadgeLocal,
  ForwardType.remote => l.forwardBadgeRemote,
  ForwardType.dynamic => l.forwardBadgeDynamic,
};

/// Description shown inside the editor sheet when selecting [type].
String forwardTypeDescription(AppLocalizations l, ForwardType type) =>
    switch (type) {
      ForwardType.local => l.forwardLocalDesc,
      ForwardType.remote => l.forwardRemoteDesc,
      ForwardType.dynamic => l.forwardDynamicDesc,
    };

/// Colors and icon for a [ForwardType] badge matching the M3 scheme.
({Color bg, Color fg, IconData icon}) forwardTypeVisual(
  ColorScheme scheme,
  ForwardType type,
) => switch (type) {
  ForwardType.local => (
    bg: scheme.primaryContainer,
    fg: scheme.onPrimaryContainer,
    icon: Icons.call_made_rounded,
  ),
  ForwardType.remote => (
    bg: scheme.tertiaryContainer,
    fg: scheme.onTertiaryContainer,
    icon: Icons.call_received_rounded,
  ),
  ForwardType.dynamic => (
    bg: scheme.secondaryContainer,
    fg: scheme.onSecondaryContainer,
    icon: Icons.hub_outlined,
  ),
};

/// Opens a right-hand side sheet to create or edit a [PortForwardRule].
Future<void> showForwardEditor(
  BuildContext context, {
  PortForwardRule? rule,
  String? initialHostId,
}) => showSideSheet<void>(
  context,
  width: 480,
  builder: (_) => ForwardEditorSheet(rule: rule, initialHostId: initialHostId),
);

class ForwardEditorSheet extends ConsumerStatefulWidget {
  const ForwardEditorSheet({super.key, this.rule, this.initialHostId});

  final PortForwardRule? rule;
  final String? initialHostId;

  @override
  ConsumerState<ForwardEditorSheet> createState() => _ForwardEditorSheetState();
}

class _ForwardEditorSheetState extends ConsumerState<ForwardEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _bindHost = TextEditingController(
    text: widget.rule?.bindHost ?? '127.0.0.1',
  );
  late final _bindPort = TextEditingController(
    text: widget.rule != null && widget.rule!.bindPort > 0
        ? '${widget.rule!.bindPort}'
        : '',
  );
  late final _targetHost = TextEditingController(
    text: widget.rule?.targetHost ?? '127.0.0.1',
  );
  late final _targetPort = TextEditingController(
    text: widget.rule != null && widget.rule!.targetPort > 0
        ? '${widget.rule!.targetPort}'
        : '',
  );
  late final _note = TextEditingController(text: widget.rule?.note ?? '');

  late ForwardType _type = widget.rule?.type ?? ForwardType.local;
  late String? _hostId = widget.rule?.hostId ?? widget.initialHostId;
  late bool _autoStart = widget.rule?.autoStart ?? false;

  bool _saving = false;
  bool _dirty = false;
  late List<Object?> _initial;

  bool get _isEdit => widget.rule != null;

  List<Object?> _snapshot() => [
    _name.text,
    _type,
    _hostId,
    _bindHost.text,
    _bindPort.text,
    _targetHost.text,
    _targetPort.text,
    _autoStart,
    _note.text,
  ];

  void _onChanged() {
    final snap = _snapshot();
    final dirty = Iterable<int>.generate(snap.length)
        .any((i) => snap[i] != _initial[i]);
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    // Default to the first saved host when creating a new rule.
    final hosts = ref.read(hostsProvider).value?.hosts ?? const <Host>[];
    if (_hostId == null && hosts.isNotEmpty) {
      _hostId = hosts.first.id;
    }
    _initial = _snapshot();
    for (final c in [
      _name,
      _bindHost,
      _bindPort,
      _targetHost,
      _targetPort,
      _note,
    ]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _bindHost,
      _bindPort,
      _targetHost,
      _targetPort,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validatePort(String? raw) {
    final v = int.tryParse((raw ?? '').trim());
    if (v == null || v < 1 || v > 65535) {
      return context.l10n.forwardPortInvalid;
    }
    return null;
  }

  String? _validateAddress(String? raw) {
    if ((raw ?? '').trim().isEmpty) return context.l10n.forwardAddressRequired;
    return null;
  }

  PortForwardRule _draftRule(String hostId) {
    final note = _note.text.trim();
    return PortForwardRule(
      id: widget.rule?.id ?? PortForwardRule.newId(),
      name: _name.text.trim(),
      type: _type,
      hostId: hostId,
      bindHost: _bindHost.text.trim().isEmpty
          ? '127.0.0.1'
          : _bindHost.text.trim(),
      bindPort: int.tryParse(_bindPort.text.trim()) ?? 0,
      targetHost: _type == ForwardType.dynamic
          ? ''
          : (_targetHost.text.trim().isEmpty
                ? '127.0.0.1'
                : _targetHost.text.trim()),
      targetPort: _type == ForwardType.dynamic
          ? 0
          : (int.tryParse(_targetPort.text.trim()) ?? 0),
      autoStart: _autoStart,
      note: note.isEmpty ? null : note,
      createdAt: widget.rule?.createdAt,
    );
  }

  Future<void> _save() async {
    if (_hostId == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(portForwardsProvider.notifier).save(_draftRule(_hostId!));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final rule = widget.rule!;
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(l.deleteForwardTitle(rule.displayName)),
        content: Text(l.deleteForwardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await ref.read(portForwardsProvider.notifier).remove(rule.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hosts = ref.watch(hostsProvider).value?.hosts ?? const <Host>[];
    final validHostIds = {for (final h in hosts) h.id};
    final selectedHostId = _hostId != null && validHostIds.contains(_hostId)
        ? _hostId
        : (hosts.isNotEmpty ? hosts.first.id : null);
    if (_hostId == null && selectedHostId != null) {
      _hostId = selectedHostId;
      _initial = _snapshot();
    }
    Host? selectedHost;
    for (final h in hosts) {
      if (h.id == selectedHostId) {
        selectedHost = h;
        break;
      }
    }

    final listenSectionTitle = switch (_type) {
      ForwardType.local => l.forwardLocalListen,
      ForwardType.remote => l.forwardRemoteListen,
      ForwardType.dynamic => l.forwardSocksListen,
    };
    final targetSectionTitle = _type == ForwardType.local
        ? l.forwardRemoteTarget
        : l.forwardLocalTarget;
    final preview = _draftRule(selectedHostId ?? '')
        .sshCommandPreview(selectedHost);

    return SideSheet(
      title: _isEdit ? l.editForward : l.newForward,
      hasUnsavedChanges: _dirty && !_saving,
      leadingActions: [
        if (_isEdit)
          TextButton.icon(
            key: const ValueKey('delete-forward'),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l.delete),
          ),
      ],
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-forward'),
          onPressed: _saving || selectedHostId == null ? null : _save,
          child: Text(l.save),
        ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              l.forwardType,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ForwardType>(
              key: const ValueKey('forward-type-selector'),
              showSelectedIcon: false,
              segments: [
                for (final t in ForwardType.values)
                  ButtonSegment<ForwardType>(
                    value: t,
                    label: Text(forwardTypeLabel(l, t)),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: (set) {
                setState(() {
                  _type = set.first;
                  if (_type == ForwardType.dynamic && _bindPort.text.isEmpty) {
                    _bindPort.text = '1080';
                  }
                });
                _onChanged();
              },
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                forwardTypeDescription(l, _type),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l.forwardHost,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (hosts.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.forwardNoHostsHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref
                            .read(navigationProvider.notifier)
                            .go(AppDestination.hosts);
                      },
                      child: Text(l.goAddHost),
                    ),
                  ],
                ),
              )
            else
              AppDropdown<String>(
                key: const ValueKey('forward-host-dropdown'),
                value: selectedHostId!,
                onChanged: (v) {
                  setState(() => _hostId = v);
                  _onChanged();
                },
                entries: [
                  for (final h in hosts)
                    AppDropdownEntry(
                      value: h.id,
                      label: h.label.trim().isEmpty
                          ? h.target
                          : '${h.displayName} (${h.target})',
                      icon: Icons.dns_outlined,
                    ),
                ],
              ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('forward-name-field'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l.forwardName,
                hintText: l.forwardNameHint,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              listenSectionTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const ValueKey('forward-bind-host-field'),
                    controller: _bindHost,
                    decoration: InputDecoration(
                      labelText: l.forwardBindAddress,
                      hintText: '127.0.0.1',
                    ),
                    validator: _validateAddress,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: const ValueKey('forward-bind-port-field'),
                    controller: _bindPort,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.forwardPort,
                      hintText: _type == ForwardType.dynamic ? '1080' : '8080',
                    ),
                    validator: _validatePort,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final addr in const ['127.0.0.1', '0.0.0.0'])
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(addr),
                    onPressed: () {
                      _bindHost.text = addr;
                    },
                  ),
              ],
            ),
            if (_type == ForwardType.remote) ...[
              const SizedBox(height: 6),
              Text(
                l.forwardRemoteGatewayHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_type != ForwardType.dynamic) ...[
              const SizedBox(height: 20),
              Text(
                targetSectionTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const ValueKey('forward-target-host-field'),
                      controller: _targetHost,
                      decoration: InputDecoration(
                        labelText: l.forwardTargetAddress,
                        hintText: '127.0.0.1',
                      ),
                      validator: _validateAddress,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey('forward-target-port-field'),
                      controller: _targetPort,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l.forwardPort,
                        hintText: _type == ForwardType.local ? '3306' : '3000',
                      ),
                      validator: _validatePort,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text(
              l.forwardCliPreview,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              key: const ValueKey('forward-cli-preview'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                preview,
                style: TextStyle(
                  fontFamily: monoFontFamily,
                  fontFamilyFallback: monoFontFallback,
                  fontSize: 12,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('forward-autostart-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.forwardAutoStart),
              subtitle: Text(l.forwardAutoStartSubtitle),
              value: _autoStart,
              onChanged: (v) {
                setState(() => _autoStart = v);
                _onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('forward-note-field'),
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.forwardNote,
                hintText: l.forwardNoteHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
