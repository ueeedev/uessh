import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';
import '../terminal/terminal_session.dart';
import 'snippet.dart';

/// Builds the terminal input string needed to execute [content] of [language].
///
/// - Single-line `shell` commands and `other` snippets run directly in the
///   current interactive shell (preserving `cd`, `export`, aliases, etc.).
/// - Multi-line `shell` / `bash` and script languages (`python`, `node`,
///   `powershell`) are wrapped in a collision-free heredoc (or PowerShell
///   here-string on Windows local terminals) so they run cleanly without
///   leaving temporary files on the server.
String buildSnippetExecutionInput({
  required SnippetLanguage language,
  required String content,
  bool windowsPowerShell = false,
}) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final trimmed = normalized.trimRight();
  if (trimmed.isEmpty) return '';

  final isMultiLine = trimmed.contains('\n');

  if (windowsPowerShell) {
    return _windowsPowerShellCommand(language, trimmed, isMultiLine);
  }

  switch (language) {
    case SnippetLanguage.shell:
      if (!isMultiLine) return '$trimmed\r';
      return _heredoc('sh -s', trimmed);
    case SnippetLanguage.bash:
      return _heredoc('bash -s', trimmed);
    case SnippetLanguage.python:
      return _heredoc('python3 -', trimmed);
    case SnippetLanguage.node:
      return _heredoc('node -', trimmed);
    case SnippetLanguage.powershell:
      return _heredoc('pwsh -NoProfile -Command -', trimmed);
    case SnippetLanguage.other:
      return isMultiLine ? '${trimmed.replaceAll('\n', '\r')}\r' : '$trimmed\r';
  }
}

/// Builds the terminal input string when the user chooses "Insert" (paste into
/// the terminal without running a single-line command automatically).
String buildSnippetInsertInput({
  required SnippetLanguage language,
  required String content,
  bool windowsPowerShell = false,
}) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final trimmed = normalized.trimRight();
  if (trimmed.isEmpty) return '';
  if (language == SnippetLanguage.shell || language == SnippetLanguage.other) {
    return trimmed;
  }
  // For script languages (Python, Bash, Node, PowerShell), prepare the
  // executable wrapper without trailing Enter so the user can review it first.
  final exec = buildSnippetExecutionInput(
    language: language,
    content: trimmed,
    windowsPowerShell: windowsPowerShell,
  );
  return exec.endsWith('\r') ? exec.substring(0, exec.length - 1) : exec;
}

String _heredoc(String interpreter, String body) {
  final delimiter = _uniqueDelimiter(body);
  // Leading space keeps interactive shell history clean when ignorespace is on.
  final lines = body.replaceAll('\n', '\r');
  return " $interpreter <<'$delimiter'\r$lines\r$delimiter\r";
}

String _uniqueDelimiter(String body) {
  const base = '__UESSH_SNIPPET__';
  final lines = body.split('\n').map((l) => l.trim()).toSet();
  if (!lines.contains(base)) return base;
  var n = 1;
  while (lines.contains('${base}_$n')) {
    n++;
  }
  return '${base}_$n';
}

String _windowsPowerShellCommand(
  SnippetLanguage language,
  String body,
  bool isMultiLine,
) {
  if (language == SnippetLanguage.powershell ||
      (language == SnippetLanguage.other && !isMultiLine)) {
    return '${body.replaceAll('\n', '\r')}\r';
  }
  final escaped = body.replaceAll('\n', '\r');
  // PowerShell single-quoted here-string: `@'` ... `'@` (only breaks if a
  // line starts with `'@`, in which case fall back to base64 / raw).
  final safeHereString = !body.split('\n').any((line) => line.startsWith("'@"));
  if (!safeHereString) {
    return '$escaped\r';
  }
  final pipeTo = switch (language) {
    SnippetLanguage.python => 'python -',
    SnippetLanguage.node => 'node -',
    SnippetLanguage.bash => 'bash -s',
    SnippetLanguage.shell => 'sh -s',
    SnippetLanguage.powershell => null,
    SnippetLanguage.other => null,
  };
  if (pipeTo == null) return '$escaped\r';
  return "@'\r$escaped\r'@ | $pipeTo\r";
}

/// Resolves any `{{var}}` placeholders in [snippet] via a dialog, then either
/// executes it or inserts it into [session].
Future<bool> runOrInsertSnippet(
  BuildContext context, {
  required Snippet snippet,
  required TerminalSession session,
  required bool execute,
}) async {
  if (session.status != SessionStatus.connected) return false;
  var content = snippet.content;
  final placeholders = snippet.placeholders;
  if (placeholders.isNotEmpty) {
    final values = await _askPlaceholderValues(context, snippet, placeholders);
    if (values == null) return false;
    content = renderSnippetTemplate(content, values);
  }
  final windowsPs = session.isLocal && Platform.isWindows;
  final payload = execute
      ? buildSnippetExecutionInput(
          language: snippet.language,
          content: content,
          windowsPowerShell: windowsPs,
        )
      : buildSnippetInsertInput(
          language: snippet.language,
          content: content,
          windowsPowerShell: windowsPs,
        );
  if (payload.isEmpty) return false;
  if (execute) {
    session.sendInput(payload);
    session.onCommandEntered?.call();
  } else {
    session.terminal.paste(payload);
  }
  return true;
}

Future<Map<String, String>?> _askPlaceholderValues(
  BuildContext context,
  Snippet snippet,
  List<String> placeholders,
) => showDialog<Map<String, String>>(
  context: context,
  builder: (_) =>
      _SnippetVarsDialog(snippetName: snippet.name, placeholders: placeholders),
);

class _SnippetVarsDialog extends StatefulWidget {
  const _SnippetVarsDialog({
    required this.snippetName,
    required this.placeholders,
  });

  final String snippetName;
  final List<String> placeholders;

  @override
  State<_SnippetVarsDialog> createState() => _SnippetVarsDialogState();
}

class _SnippetVarsDialogState extends State<_SnippetVarsDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final name in widget.placeholders) name: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    Navigator.of(context)
        .pop({for (final e in _controllers.entries) e.key: e.value.text});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const ValueKey('snippet-vars-dialog'),
      title: Text(l.snippetFillVarsTitle(widget.snippetName)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.placeholders.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                TextField(
                  key: ValueKey('snippet-var-${widget.placeholders[i]}'),
                  controller: _controllers[widget.placeholders[i]],
                  autofocus: i == 0,
                  style: TextStyle(
                    fontFamily: monoFontFamily,
                    fontFamilyFallback: monoFontFallback,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.placeholders[i],
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: i == widget.placeholders.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: i == widget.placeholders.length - 1
                      ? (_) => _submit()
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('snippet-vars-submit'),
          onPressed: _submit,
          child: Text(l.snippetRun),
        ),
      ],
    );
  }
}
