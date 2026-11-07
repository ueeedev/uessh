import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/terminal_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/side_sheet.dart';
import 'host.dart';
import 'hosts_providers.dart';

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

  /// Selected existing group (null = ungrouped).
  late String? _groupId = widget.host?.groupId;

  /// A group typed in this sheet; created only when the host is saved.
  String? _newGroupName;
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
    final file = await openFile(confirmButtonText: '导入');
    if (file == null) return;
    final text = await file.readAsString();
    setState(() {
      _privateKey.text = text.trim();
      _keyError = null;
    });
  }

  /// Checks the key parses; returns an error message or null.
  String? _validateKey() {
    final pem = _privateKey.text.trim();
    if (pem.isEmpty) return '请粘贴或导入私钥';
    try {
      final encrypted = SSHKeyPair.isEncryptedPem(pem);
      // An encrypted key without a saved passphrase is fine: we ask on connect.
      if (encrypted && _passphrase.text.isEmpty) return null;
      SSHKeyPair.fromPem(pem, encrypted ? _passphrase.text : null);
      return null;
    } on SSHKeyDecryptError {
      return '私钥口令不正确';
    } catch (_) {
      return '无法识别私钥格式（支持 OpenSSH、PEM 格式的 RSA / ECDSA / Ed25519）';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_authMethod == AuthMethod.key) {
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
    );
    final secrets = _authMethod == AuthMethod.password
        ? HostSecrets(password: _password.text)
        : HostSecrets(
            privateKey: _privateKey.text.trim(),
            passphrase: _passphrase.text,
          );

    try {
      await ref
          .read(hostsProvider.notifier)
          .save(host, secrets, newGroupName: _newGroupName);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SideSheet(
      title: _isEdit ? '编辑主机' : '新建主机',
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
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '例如：生产服务器（可选）',
                      ),
                    ),
                    const SizedBox(height: 16),
                    GroupPicker(
                      groups:
                          ref.watch(hostsProvider).value?.groups ?? const [],
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
                            decoration: const InputDecoration(
                              labelText: '地址',
                              hintText: 'IP 或域名',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? '请输入地址'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: _port,
                            decoration: const InputDecoration(labelText: '端口'),
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
                      decoration: const InputDecoration(labelText: '用户名'),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 20),
                    Text('认证方式', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<AuthMethod>(
                      segments: const [
                        ButtonSegment(
                          value: AuthMethod.password,
                          icon: Icon(Icons.password),
                          label: Text('密码'),
                        ),
                        ButtonSegment(
                          value: AuthMethod.key,
                          icon: Icon(Icons.key),
                          label: Text('私钥'),
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
                          labelText: '密码',
                          helperText: '保存在系统钥匙串中；留空则每次连接时询问',
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? '显示' : '隐藏',
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
                          labelText: '私钥',
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
                          label: const Text('从文件导入'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _passphrase,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '私钥口令',
                          helperText: '私钥没有加密就留空；加密了但留空则每次连接时询问',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          // maybePop, so unsaved changes ask for confirmation first.
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loadingSecrets ? null : _save,
          child: const Text('保存'),
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
      setState(() => _error = '请输入分组名称');
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

  @override
  Widget build(BuildContext context) {
    if (_adding) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _confirmNew(),
              decoration: InputDecoration(
                labelText: '新分组名称',
                hintText: '例如：生产环境',
                errorText: _error,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: IconButton.filledTonal(
              tooltip: '添加分组',
              icon: const Icon(Icons.check),
              onPressed: _confirmNew,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: IconButton(
              tooltip: '取消新建',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _adding = false;
                _error = null;
                _name.clear();
              }),
            ),
          ),
        ],
      );
    }

    final selected = widget.newGroupName != null
        ? _pending
        : (widget.groups.any((g) => g.id == widget.groupId)
              ? widget.groupId!
              : _none);
    return Row(
      children: [
        Expanded(
          child: AppDropdown<String>(
            label: '分组',
            leadingIcon: Icons.folder_outlined,
            value: selected,
            onChanged: (v) {
              if (v == _pending) return;
              widget.onChanged(v == _none ? null : v, null);
            },
            entries: [
              const AppDropdownEntry(
                value: _none,
                label: '未分组',
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
                  label: '${widget.newGroupName}（新）',
                  icon: Icons.create_new_folder_outlined,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('新建分组'),
        ),
      ],
    );
  }
}
