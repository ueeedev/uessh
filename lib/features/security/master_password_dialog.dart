import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault.dart';
import 'vault_controller.dart';
import '../../l10n/l10n.dart';

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
        _currentError = context.l10n.wrongMasterPassword;
      });
    }
  }

  String? _validateNew(String? v) {
    if ((v ?? '').length < minMasterPasswordLength) {
      return context.l10n.minChars(minMasterPasswordLength);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, intro, button) = switch (widget.action) {
      MasterPasswordAction.set => (
        context.l10n.setMasterPassword,
        context.l10n.setMasterPasswordIntro,
        context.l10n.turnOn,
      ),
      MasterPasswordAction.change => (
        context.l10n.changeMasterPassword,
        null,
        context.l10n.change,
      ),
      MasterPasswordAction.remove => (
        context.l10n.turnOffMasterPassword,
        context.l10n.turnOffIntro,
        context.l10n.turnOffMasterPassword,
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
                    labelText: context.l10n.currentMasterPassword,
                    errorText: _currentError,
                  ),
                  validator: (v) => (v ?? '').isEmpty
                      ? context.l10n.enterCurrentMasterPassword
                      : null,
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
                    labelText: _needsCurrent
                        ? context.l10n.newMasterPassword
                        : context.l10n.masterPassword,
                    helperText: context.l10n.minChars(minMasterPasswordLength),
                  ),
                  validator: _validateNew,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: context.l10n.confirmPassword,
                  ),
                  validator: (v) =>
                      v != _next.text ? context.l10n.passwordsDontMatch : null,
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
          child: Text(context.l10n.cancel),
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
