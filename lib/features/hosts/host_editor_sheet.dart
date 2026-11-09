import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/side_sheet.dart';
import 'host.dart';
import 'host_icon_picker.dart';
import '../keys/keys_providers.dart';
import 'hosts_providers.dart';
import '../../l10n/l10n.dart';
import '../../widgets/toasts.dart';

/// Opens the editor as a side sheet from the right. Pass [host] to edit,
/// or null to create.
Future<void> showHostEditor(BuildContext context, {Host? host}) {
  return showSideSheet<void>(
    context,
    builder: (_) => HostEditorSheet(host: host),
  );
}

class HostEditorSheet extends ConsumerStatefulWidget {
  const HostEditorSheet({super.key, this.host});

  final Host? host;

  @override
  ConsumerState<HostEditorSheet> createState() => _HostEditorSheetState();
}

class _HostEditorSheetState extends ConsumerState<HostEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.host?.label);
  late final _address = TextEditingController(text: widget.host?.address);
  late final _port = TextEditingController(text: '${widget.host?.port ?? 22}');
  late final _username = TextEditingController(text: widget.host?.username);
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();

  late AuthMethod _authMethod = widget.host?.authMethod ?? AuthMethod.password;

  /// Card icon: letter, symbol or flag.
  late HostIcon _icon = widget.host?.icon ?? HostIcon.letter;

  /// Selected existing group (null = ungrouped).
  late String? _groupId = widget.host?.groupId;

  /// A group typed in this sheet; created only when the host is saved.
  String? _newGroupName;

  /// Saved key to log in with ('' = use the key pasted below).
  late String _keyId = widget.host?.keyId ?? '';
  bool _obscurePassword = true;
  bool _saving = false;
  bool _loadingSecrets = false;
  String? _keyError;

  /// Field values when the sheet opened (after secrets loaded), used to
  /// tell whether anything changed.
  List<Object?>? _initial;
  bool _dirty = false;

  bool get _isEdit => widget.host != null;

  List<TextEditingController> get _controllers => [
    _label,
    _address,
    _port,
    _username,
    _password,
    _privateKey,
    _passphrase,
  ];

  List<Object?> _snapshot() => [
    for (final c in _controllers) c.text,
    _authMethod,
    _groupId,
    _newGroupName,
    _keyId,
    _icon,
  ];

  void _updateDirty() {
    final initial = _initial;
    final snap = _snapshot();
    final dirty =
        initial != null &&
        Iterable<int>.generate(snap.length).any((i) => snap[i] != initial[i]);
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  @override
  void initState() {
    super.initState();
    for (final c in _controllers) {
      c.addListener(_updateDirty);
    }
    if (_isEdit) {
      _loadSecrets();
    } else {
      _initial = _snapshot();
    }
  }

  Future<void> _loadSecrets() async {
    setState(() => _loadingSecrets = true);
    final s = await ref
        .read(hostRepositoryProvider)
        .readSecrets(widget.host!.id);
    if (!mounted) return;
    setState(() {
      _password.text = s.password ?? '';
      _privateKey.text = s.privateKey ?? '';
      _passphrase.text = s.passphrase ?? '';
      _loadingSecrets = false;
      _initial = _snapshot();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _importKeyFile() async {
    final file = await openFile(confirmButtonText: context.l10n.importAction);
    if (file == null) return;
    final text = await file.readAsString();
    setState(() {
      _privateKey.text = text.trim();
      _keyError = null;
    });
  }

  /// Checks the key parses; returns an error message or null.
  /// Like [_usesSavedKey] but rebuilds when the key list changes.
  bool _usesSavedKeyWatched(WidgetRef ref) {
    final keys = ref.watch(keysProvider).value ?? [];
    return _keyId.isNotEmpty && keys.any((k) => k.id == _keyId);
  }

  /// True when a saved key (that still exists) is selected.
  bool get _usesSavedKey {
    if (_keyId.isEmpty) return false;
    final keys = ref.read(keysProvider).value ?? [];
    return keys.any((k) => k.id == _keyId);
  }

  String? _validateKey() {
    final pem = _privateKey.text.trim();
    if (pem.isEmpty) return context.l10n.keyRequired;
    try {
      final encrypted = SSHKeyPair.isEncryptedPem(pem);
      // An encrypted key without a saved passphrase is fine: we ask on connect.
      if (encrypted && _passphrase.text.isEmpty) return null;
      SSHKeyPair.fromPem(pem, encrypted ? _passphrase.text : null);
      return null;
    } on SSHKeyDecryptError {
      return context.l10n.keyWrongPassphrase;
    } catch (_) {
      return context.l10n.keyUnrecognized;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_authMethod == AuthMethod.key && !_usesSavedKey) {
      final error = _validateKey();
      setState(() => _keyError = error);
      if (error != null) return;
    }

    setState(() => _saving = true);
    final host = Host(
      id: widget.host?.id ?? Host.newId(),
      label: _label.text.trim(),
      address: _address.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      authMethod: _authMethod,
      groupId: _newGroupName == null ? _groupId : null,
      keyId: _authMethod == AuthMethod.key && _usesSavedKey ? _keyId : null,
      icon: _icon,
    );
    final secrets = _authMethod == AuthMethod.password
        ? HostSecrets(password: _password.text)
        : (_usesSavedKey
              ? const HostSecrets() // the saved key holds the secrets
              : HostSecrets(
                  privateKey: _privateKey.text.trim(),
                  passphrase: _passphrase.text,
                ));

    try {
      await ref
          .read(hostsProvider.notifier)
          .save(host, secrets, newGroupName: _newGroupName);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context.l10n.saveFailed('$e'), kind: ToastKind.error);
    }
  }

  Future<void> _delete() async {
    final host = widget.host!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(context.l10n.deleteHostTitle(host.displayName)),
        content: Text(context.l10n.deleteHostBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await ref.read(hostsProvider.notifier).remove(host.id);
    // pop, not maybePop: deleting needs no "discard changes?" question.
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SideSheet(
      title: _isEdit ? context.l10n.editHost : context.l10n.newHost,
      hasUnsavedChanges: _dirty && !_saving,
      body: _loadingSecrets
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _label,
                      decoration: InputDecoration(
                        labelText: context.l10n.fieldName,
                        hintText: context.l10n.hostNameHint,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GroupPicker(
                      groups: ref.watch(hostsProvider).value?.groups ?? [],
                      groupId: _groupId,
                      newGroupName: _newGroupName,
                      onChanged: (groupId, newName) {
                        setState(() {
                          _groupId = groupId;
                          _newGroupName = newName;
                        });
                        _updateDirty();
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _address,
                            autofocus: !_isEdit,
                            decoration: InputDecoration(
                              labelText: context.l10n.fieldAddress,
                              hintText: context.l10n.addressHint,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? context.l10n.addressRequired
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: _port,
                            decoration: InputDecoration(
                              labelText: context.l10n.fieldPort,
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (v) {
                              final p = int.tryParse(v ?? '');
                              return (p == null || p < 1 || p > 65535)
                                  ? '1-65535'
                                  : null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _username,
                      decoration: InputDecoration(
                        labelText: context.l10n.fieldUsername,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? context.l10n.usernameRequired
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.authMethod,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<AuthMethod>(
                      segments: [
                        ButtonSegment(
                          value: AuthMethod.password,
                          icon: const Icon(Icons.password),
                          label: Text(context.l10n.authPassword),
                        ),
                        ButtonSegment(
                          value: AuthMethod.key,
                          icon: const Icon(Icons.key),
                          label: Text(context.l10n.authKey),
                        ),
                      ],
                      selected: {_authMethod},
                      onSelectionChanged: (s) {
                        setState(() => _authMethod = s.first);
                        _updateDirty();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_authMethod == AuthMethod.password)
                      TextFormField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: context.l10n.authPassword,
                          helperText: context.l10n.passwordHelper,
                          helperMaxLines: 2,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? context.l10n.show
                                : context.l10n.hide,
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      _KeySource(
                        keyId: _keyId,
                        onChanged: (v) {
                          setState(() {
                            _keyId = v;
                            _keyError = null;
                          });
                          _updateDirty();
                        },
                      ),
                      if (!_usesSavedKeyWatched(ref)) ...[
                        TextField(
                          controller: _privateKey,
                          minLines: 4,
                          maxLines: 8,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: monoFontFamily,
                            fontFamilyFallback: monoFontFallback,
                          ),
                          onChanged: (_) {
                            if (_keyError != null) {
                              setState(() => _keyError = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: context.l10n.authKey,
                            hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                            alignLabelWithHint: true,
                            errorText: _keyError,
                            errorMaxLines: 2,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _importKeyFile,
                            icon: const Icon(Icons.file_open_outlined),
                            label: Text(context.l10n.importFromFile),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passphrase,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.fieldPassphrase,
                            helperText: context.l10n.passphraseHelper,
                            helperMaxLines: 2,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    // Less used options, folded away at the bottom.
                    MoreSettings(
                      child: HostIconPicker(
                        value: _icon,
                        label: _label,
                        address: _address,
                        onChanged: (icon) {
                          setState(() => _icon = icon);
                          _updateDirty();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
      leadingActions: [
        if (_isEdit)
          TextButton.icon(
            key: const ValueKey('delete-host'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(context.l10n.delete),
          ),
      ],
      actions: [
        TextButton(
          // maybePop, so unsaved changes ask for confirmation first.
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving || _loadingSecrets ? null : _save,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

/// Choose a group, or type a new one. A new group is only reported back
/// through [onChanged] (as `newName`); the caller creates it on save.
class GroupPicker extends StatefulWidget {
  const GroupPicker({
    super.key,
    required this.groups,
    required this.groupId,
    required this.newGroupName,
    required this.onChanged,
  });

  final List<HostGroup> groups;
  final String? groupId;
  final String? newGroupName;
  final void Function(String? groupId, String? newName) onChanged;

  @override
  State<GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<GroupPicker> {
  static const _none = '';
  static const _pending = '\u0000new';

  bool _adding = false;
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _confirmNew() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.groupNameRequired);
      return;
    }
    final key = name.toLowerCase();
    final existing = widget.groups.where((g) => g.name.toLowerCase() == key);
    if (existing.isNotEmpty) {
      widget.onChanged(existing.first.id, null); // reuse the same-name group
    } else {
      widget.onChanged(null, name);
    }
    setState(() {
      _adding = false;
      _error = null;
      _name.clear();
    });
  }

  /// Same width in both modes, so the field on the left never changes
  /// size when the buttons swap.
  static const _actionsWidth = 132.0;

  static Widget _swap(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      );

  static Widget _topStack(Widget? current, List<Widget> previous) =>
      Stack(alignment: Alignment.topLeft, children: [...previous, ?current]);

  void _cancelNew() => setState(() {
    _adding = false;
    _error = null;
    _name.clear();
  });

  @override
  Widget build(BuildContext context) {
    final selected = widget.newGroupName != null
        ? _pending
        : (widget.groups.any((g) => g.id == widget.groupId)
              ? widget.groupId!
              : _none);

    final field = _adding
        ? TextField(
            key: const ValueKey('new-group-field'),
            controller: _name,
            autofocus: true,
            maxLength: 40,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _confirmNew(),
            decoration: InputDecoration(
              labelText: context.l10n.newGroupName,
              hintText: context.l10n.newGroupHint,
              errorText: _error,
              counterText: '',
            ),
          )
        : AppDropdown<String>(
            key: const ValueKey('group-dropdown'),
            label: context.l10n.group,
            leadingIcon: Icons.folder_outlined,
            value: selected,
            onChanged: (v) {
              if (v == _pending) return;
              widget.onChanged(v == _none ? null : v, null);
            },
            entries: [
              AppDropdownEntry(
                value: _none,
                label: context.l10n.ungrouped,
                icon: Icons.folder_off_outlined,
              ),
              for (final g in widget.groups)
                AppDropdownEntry(
                  value: g.id,
                  label: g.name,
                  icon: Icons.folder_outlined,
                ),
              if (widget.newGroupName != null)
                AppDropdownEntry(
                  value: _pending,
                  label: context.l10n.newGroupPending(widget.newGroupName!),
                  icon: Icons.create_new_folder_outlined,
                ),
            ],
          );

    final buttons = _adding
        ? Row(
            key: const ValueKey('confirm-cancel'),
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                tooltip: context.l10n.addGroup,
                icon: const Icon(Icons.check),
                onPressed: _confirmNew,
              ),
              IconButton(
                tooltip: context.l10n.cancelNewGroup,
                icon: const Icon(Icons.close),
                onPressed: _cancelNew,
              ),
            ],
          )
        : Align(
            key: const ValueKey('new-group-button'),
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(context.l10n.newGroup),
              ),
            ),
          );

    const duration = Duration(milliseconds: 220);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _swap,
            layoutBuilder: _topStack,
            child: field,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          key: const ValueKey('group-actions'),
          width: _actionsWidth,
          height: 48,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _swap,
            child: buttons,
          ),
        ),
      ],
    );
  }
}

/// Pick a saved key (Keys page) or paste one for this host only.
class _KeySource extends ConsumerWidget {
  const _KeySource({required this.keyId, required this.onChanged});

  final String keyId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(keysProvider).value ?? [];
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          context.l10n.savedKeysHint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    final value = keys.any((k) => k.id == keyId) ? keyId : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppDropdown<String>(
        key: const ValueKey('key-source'),
        label: context.l10n.keyToUse,
        leadingIcon: Icons.key,
        value: value,
        onChanged: onChanged,
        entries: [
          for (final k in keys)
            AppDropdownEntry(value: k.id, label: k.name, icon: Icons.key),
          AppDropdownEntry(
            value: '',
            label: context.l10n.pasteKeyOption,
            icon: Icons.content_paste,
          ),
        ],
      ),
    );
  }
}

/// A "More settings" button that unfolds [child] below it, then scrolls
/// it into view.
class MoreSettings extends StatefulWidget {
  const MoreSettings({super.key, required this.child});

  final Widget child;

  @override
  State<MoreSettings> createState() => _MoreSettingsState();
}

class _MoreSettingsState extends State<MoreSettings> {
  static const _duration = Duration(milliseconds: 250);
  final _contentKey = GlobalKey();
  bool _open = false;

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (!_open) return;
    await Future<void>.delayed(_duration);
    final ctx = _contentKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: _duration,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                key: const ValueKey('more-settings'),
                onPressed: _toggle,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                iconAlignment: IconAlignment.end,
                icon: AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more),
                ),
                label: Text(
                  _open ? context.l10n.lessSettings : context.l10n.moreSettings,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        AnimatedSize(
          duration: _duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  key: _contentKey,
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
