import 'package:flutter/material.dart';

import '../../theme/terminal_theme.dart';
import 'known_hosts.dart';
import 'terminal_session.dart';

/// Shows M3 dialogs on the root navigator.
class DialogSessionPrompts implements SessionPrompts {
  DialogSessionPrompts(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  BuildContext? get _context => navigatorKey.currentContext;

  @override
  Future<bool> confirmHostKey({
    required String hostPort,
    required KnownHostEntry offered,
    KnownHostEntry? previous,
  }) async {
    final context = _context;
    if (context == null) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HostKeyDialog(
        hostPort: hostPort,
        offered: offered,
        previous: previous,
      ),
    );
    return result ?? false;
  }

  @override
  Future<String?> askSecret({required String title, required String message}) {
    final context = _context;
    if (context == null) return Future.value(null);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SecretDialog(title: title, message: message),
    );
  }
}

class HostKeyDialog extends StatelessWidget {
  const HostKeyDialog({
    super.key,
    required this.hostPort,
    required this.offered,
    this.previous,
  });

  final String hostPort;
  final KnownHostEntry offered;
  final KnownHostEntry? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = previous != null;
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
    );

    return AlertDialog(
      icon: Icon(
        changed ? Icons.gpp_bad_outlined : Icons.fingerprint,
        color: changed ? theme.colorScheme.error : null,
      ),
      title: Text(changed ? '主机密钥已变化' : '首次连接这台主机'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changed
                  ? '$hostPort 的主机密钥和上次不同。可能是服务器重装了系统，也可能有人在拦截连接。确认无误后再继续。'
                  : '无法确认 $hostPort 的身份。请核对下面的指纹，确认是你的服务器后再继续。',
            ),
            const SizedBox(height: 16),
            if (changed) ...[
              Text(
                '之前的指纹（${previous!.keyType}）',
                style: theme.textTheme.labelMedium,
              ),
              SelectableText(previous!.fingerprint, style: mono),
              const SizedBox(height: 12),
            ],
            Text(
              changed ? '现在的指纹（${offered.keyType}）' : offered.keyType,
              style: theme.textTheme.labelMedium,
            ),
            SelectableText(offered.fingerprint, style: mono),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        changed
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然信任'),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('信任并连接'),
              ),
      ],
    );
  }
}

class SecretDialog extends StatefulWidget {
  const SecretDialog({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<SecretDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示' : '隐藏',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
