import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/side_sheet.dart';
import '../hosts/hosts_providers.dart';
import 'keys_providers.dart';
import 'ssh_key.dart';
import '../../l10n/l10n.dart';

/// Add a key (null) or edit [key], in a side sheet from the right.
Future<void> showKeyEditor(BuildContext context, {SshKey? key}) =>
    showSideSheet<void>(context, builder: (_) => KeyEditorSheet(sshKey: key));

class KeyEditorSheet extends ConsumerStatefulWidget {
  const KeyEditorSheet({super.key, this.sshKey});

  final SshKey? sshKey;

  @override
  ConsumerState<KeyEditorSheet> createState() => _KeyEditorSheetState();
}

class _KeyEditorSheetState extends ConsumerState<KeyEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.sshKey?.name);
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String? _keyError;
  List<String>? _initial;
  bool _dirty = false;

  bool get _isEdit => widget.sshKey != null;

  List<TextEditingController> get _controllers => [
    _name,
    _privateKey,
    _passphrase,
  ];

  List<String> _snapshot() => [for (final c in _controllers) c.text];

  void _updateDirty() {
    final initial = _initial;
    final snap = _snapshot();
    final dirty =
        initial != null &&
        Iterable<int>.generate(3).any((i) => snap[i] != initial[i]);
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
    setState(() => _loading = true);
    final s = await ref
        .read(keyRepositoryProvider)
        .readSecrets(widget.sshKey!.id);
    if (!mounted) return;
    setState(() {
      _privateKey.text = s.privateKey ?? '';
      _passphrase.text = s.passphrase ?? '';
      _loading = false;
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

  Future<void> _importFile() async {
    final file = await openFile(confirmButtonText: context.l10n.importAction);
    if (file == null) return;
    final text = (await file.readAsString()).trim();
    setState(() {
      _privateKey.text = text;
      _keyError = null;
      if (_name.text.trim().isEmpty) _name.text = file.name;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _keyError = null;
    });
    final KeyInfo info;
    try {
      info = await inspectPrivateKey(
        _privateKey.text,
        _passphrase.text,
        comment: _name.text.trim(),
      );
    } on InvalidKeyException catch (e) {
      setState(() {
        _saving = false;
        _keyError = e.message;
      });
      return;
    }
    final key = SshKey(
      id: widget.sshKey?.id ?? SshKey.newId(),
      name: _name.text.trim(),
      keyType: info.keyType,
      fingerprint: info.fingerprint,
      publicKey: info.publicKey,
    );
    await ref
        .read(keysProvider.notifier)
        .save(
          key,
          KeySecrets(
            privateKey: _privateKey.text.trim(),
            passphrase: _passphrase.text,
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final key = widget.sshKey!;
    final hosts = ref.read(hostsProvider).value?.hosts ?? [];
    final users = hosts.where((h) => h.keyId == key.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(context.l10n.deleteKeyTitle(key.name)),
        content: Text(
          users == 0
              ? context.l10n.deleteKeyBody
              : context.l10n.deleteKeyInUse(users),
        ),
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
    await ref.read(keysProvider.notifier).remove(key.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _copyPublicKey(String publicKey) async {
    await Clipboard.setData(ClipboardData(text: publicKey));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.publicKeyCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
    );
    final existing = widget.sshKey;

    return SideSheet(
      title: _isEdit ? context.l10n.editKey : context.l10n.addKey,
      hasUnsavedChanges: _dirty && !_saving,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: !_isEdit,
                    decoration: InputDecoration(
                      labelText: context.l10n.fieldName,
                      hintText: context.l10n.keyNameHint,
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? context.l10n.nameRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _privateKey,
                    minLines: 5,
                    maxLines: 10,
                    style: mono,
                    onChanged: (_) {
                      if (_keyError != null) setState(() => _keyError = null);
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
                      onPressed: _importFile,
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
                  if (existing?.publicKey != null) ...[
                    const SizedBox(height: 24),
                    _InfoRow(
                      label: context.l10n.keyType,
                      value: existing!.keyType ?? '',
                    ),
                    _InfoRow(
                      label: context.l10n.fingerprint,
                      value: existing.fingerprint ?? '',
                      style: mono,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _copyPublicKey(existing.publicKey!),
                      icon: const Icon(Icons.copy),
                      label: Text(context.l10n.copyPublicKey),
                    ),
                  ],
                ],
              ),
            ),
      leadingActions: [
        if (_isEdit)
          TextButton.icon(
            key: const ValueKey('delete-key'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(context.l10n.delete),
          ),
      ],
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: style ?? theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
