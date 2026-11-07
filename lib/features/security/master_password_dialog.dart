import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault.dart';
import 'vault_controller.dart';

enum MasterPasswordAction { set, change, remove }

const minMasterPasswordLength = 8;

/// Turns the master password on, changes it, or turns it off. Performs the
/// change itself and pops `true` on success.
class MasterPasswordDialog extends ConsumerStatefulWidget {
  const MasterPasswordDialog({super.key, required this.action});

  final MasterPasswordAction action;

  @override
  ConsumerState<MasterPasswordDialog> createState() =>
      _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends ConsumerState<MasterPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _currentError;

  bool get _needsCurrent => widget.action != MasterPasswordAction.set;
  bool get _needsNew => widget.action != MasterPasswordAction.remove;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _currentError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final vault = ref.read(vaultControllerProvider.notifier);
    try {
      switch (widget.action) {
        case MasterPasswordAction.set:
          await vault.setPassword(_next.text);
        case MasterPasswordAction.change:
          await vault.changePassword(_current.text, _next.text);
        case MasterPasswordAction.remove:
          await vault.removePassword(_current.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on WrongPasswordException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _currentError = '主密码不正确';
      });
    }
  }

  String? _validateNew(String? v) {
    if ((v ?? '').length < minMasterPasswordLength) {
      return '至少 $minMasterPasswordLength 个字符';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, intro, button) = switch (widget.action) {
      MasterPasswordAction.set => (
        '设置主密码',
        '开启后，每次打开 uessh 需要输入一次主密码，才能使用已保存的密码和私钥。'
            '主密码无法找回，请务必记住。',
        '开启',
      ),
      MasterPasswordAction.change => ('修改主密码', null, '修改'),
      MasterPasswordAction.remove => (
        '关闭主密码',
        '关闭后，打开 uessh 不再需要输入主密码，凭据改用本机密钥加密保存。',
        '关闭主密码',
      ),
    };

    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (intro != null) ...[
                Text(intro, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              if (_needsCurrent) ...[
                TextFormField(
                  controller: _current,
                  autofocus: true,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: '当前主密码',
                    errorText: _currentError,
                  ),
                  validator: (v) => (v ?? '').isEmpty ? '请输入当前主密码' : null,
                  onFieldSubmitted: (_) => _needsNew ? null : _submit(),
                ),
                const SizedBox(height: 16),
              ],
              if (_needsNew) ...[
                TextFormField(
                  controller: _next,
                  autofocus: !_needsCurrent,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: _needsCurrent ? '新主密码' : '主密码',
                    helperText: '至少 $minMasterPasswordLength 个字符',
                  ),
                  validator: _validateNew,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: '再输入一次'),
                  validator: (v) => v != _next.text ? '两次输入不一致' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(button),
        ),
      ],
    );
  }
}
