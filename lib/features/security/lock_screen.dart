import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vault.dart';
import '../settings/settings_providers.dart';
import 'vault_controller.dart';

/// Sits above the whole app (MaterialApp.builder). While the vault is
/// locked it covers everything, dialogs included, with the lock screen;
/// the app underneath keeps its state and SSH sessions stay connected.
/// Also locks the vault after the configured idle time.
class VaultGate extends ConsumerStatefulWidget {
  const VaultGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate> {
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _restartIdleTimer();
    return false; // never swallow keys
  }

  void _restartIdleTimer() {
    _idle?.cancel();
    final vault = ref.read(vaultControllerProvider);
    final minutes = ref.read(settingsProvider).autoLockMinutes;
    if (!vault.hasPassword || vault.locked || minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), () {
      if (mounted) ref.read(vaultControllerProvider.notifier).lock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(vaultControllerProvider.select((s) => s.locked));
    // Restart the countdown whenever the lock state or the setting changes.
    ref.listen(vaultControllerProvider, (_, _) => _restartIdleTimer());
    ref.listen(
      settingsProvider.select((s) => s.autoLockMinutes),
      (_, _) => _restartIdleTimer(),
    );
    if (_idle == null && !locked) _restartIdleTimer();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restartIdleTimer(),
      onPointerSignal: (_) => _restartIdleTimer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: locked,
            child: TickerMode(enabled: !locked, child: widget.child),
          ),
          if (locked)
            // Own overlay: text fields need one, and this sits outside
            // the Navigator's.
            Overlay.wrap(child: const LockScreen()),
        ],
      ),
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _obscure = true;
  bool _confirmReset = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(vaultControllerProvider.notifier).unlock(_password.text);
    } on WrongPasswordException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '主密码不正确';
      });
      _password.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _password.text.length,
      );
      _focus.requestFocus();
    }
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    await ref.read(vaultControllerProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: SizedBox(
          width: 360,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _confirmReset ? _buildReset(theme) : _buildUnlock(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlock(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('unlock'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/logo.png', width: 88, height: 88),
        const SizedBox(height: 20),
        Text('uessh 已锁定', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '输入主密码解锁已保存的密码和私钥',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _password,
          focusNode: _focus,
          autofocus: true,
          obscureText: _obscure,
          enabled: !_busy,
          onSubmitted: (_) => _unlock(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: '主密码',
            prefixIcon: const Icon(Icons.lock_outline),
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: _obscure ? '显示' : '隐藏',
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: _busy ? null : _unlock,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('解锁'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _confirmReset = true),
          child: const Text('忘记主密码？'),
        ),
      ],
    );
  }

  Widget _buildReset(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('reset'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.warning_amber_rounded, size: 48, color: scheme.error),
        const SizedBox(height: 16),
        Text(
          '重置保险库？',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          '主密码无法找回。重置会删除所有已保存的密码、私钥和口令，'
          '主机列表和分组会保留，之后需要重新填写登录信息。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size.fromHeight(44),
          ),
          onPressed: _busy ? null : _reset,
          child: const Text('删除已保存的凭据并重置'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _confirmReset = false),
          child: const Text('返回'),
        ),
      ],
    );
  }
}
