import 'package:flutter/material.dart';

import '../../theme/terminal_theme.dart';
import 'known_hosts.dart';
import 'terminal_session.dart';
import '../../l10n/l10n.dart';

/// Shows M3 dialogs on the root navigator.
class DialogSessionPrompts implements SessionPrompts {
  const DialogSessionPrompts(this.navigatorKey);

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
      title: Text(
        changed
            ? context.l10n.hostKeyChangedTitle
            : context.l10n.hostKeyNewTitle,
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changed
                  ? context.l10n.hostKeyChangedBody(hostPort)
                  : context.l10n.hostKeyNewBody(hostPort),
            ),
            const SizedBox(height: 16),
            if (changed) ...[
              Text(
                context.l10n.previousFingerprint(previous!.keyType),
                style: theme.textTheme.labelMedium,
              ),
              SelectableText(previous!.fingerprint, style: mono),
              const SizedBox(height: 12),
            ],
            Text(
              changed
                  ? context.l10n.currentFingerprint(offered.keyType)
                  : offered.keyType,
              style: theme.textTheme.labelMedium,
            ),
            SelectableText(offered.fingerprint, style: mono),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        changed
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.trustAnyway),
              )
            : FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.trustAndConnect),
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
                  tooltip: _obscure ? context.l10n.show : context.l10n.hide,
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
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.ok)),
      ],
    );
  }
}
