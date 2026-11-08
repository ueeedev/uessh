import 'package:xterm2/xterm.dart';

/// Kinds of words colored in the command being typed.
enum HighlightToken {
  command,
  dangerous,
  option,
  string,
  variable,
  operator,
  comment,
}

/// Default colors (ARGB), readable on dark and light terminals.
const defaultHighlightColors = <HighlightToken, int>{
  HighlightToken.command: 0xFF3FB950,
  HighlightToken.dangerous: 0xFFF85149,
  HighlightToken.option: 0xFF39C5CF,
  HighlightToken.string: 0xFFD29922,
  HighlightToken.variable: 0xFFBC8CFF,
  HighlightToken.operator: 0xFF58A6FF,
  HighlightToken.comment: 0xFF8B949E,
};

/// On/off plus a color for each kind.
typedef HighlightSettings = ({bool enabled, Map<HighlightToken, int> colors});

/// A colored span of a command line: [start] inclusive, [end] exclusive.
typedef HighlightSpan = ({int start, int end, HighlightToken token});

/// Commands that delete, overwrite or stop things.
const dangerousCommands = {
  'rm', 'rmdir', 'dd', 'mkfs', 'shred', 'wipefs', 'fdisk', 'sfdisk', //
  'parted', 'shutdown', 'reboot', 'poweroff', 'halt', 'init', 'kill',
  'killall', 'pkill', 'chmod', 'chown', 'truncate', 'mkswap', 'crontab',
};

/// Commands that run the word after them as a command.
const _prefixCommands = {
  'sudo', 'doas', 'env', 'time', 'nohup', 'nice', 'exec', 'command', //
  'builtin', 'xargs', 'watch', 'timeout', 'strace', 'stdbuf',
};

bool _isSpace(String c) => c == ' ' || c == '\t';
bool _isOperatorChar(String c) =>
    c == '|' ||
    c == '&' ||
    c == ';' ||
    c == '<' ||
    c == '>' ||
    c == '(' ||
    c == ')' ||
    c == '`';

/// Splits a shell command line (bash / zsh syntax) into colored spans.
/// Unmarked text is a plain argument.
List<HighlightSpan> highlightCommand(String line) {
  final spans = <HighlightSpan>[];
  void add(int start, int end, HighlightToken token) {
    if (end > start) spans.add((start: start, end: end, token: token));
  }

  var commandPosition = true;
  var i = 0;
  final n = line.length;
  while (i < n) {
    final c = line[i];
    if (_isSpace(c)) {
      i++;
      continue;
    }
    if (c == '#') {
      add(i, n, HighlightToken.comment);
      break;
    }
    if (c == r'$' && i + 1 < n && line[i + 1] == '(') {
      add(i, i + 2, HighlightToken.operator);
      i += 2;
      commandPosition = true;
      continue;
    }
    if (_isOperatorChar(c)) {
      final start = i;
      // Redirects like 2> and &> are one operator.
      while (i < n &&
          _isOperatorChar(line[i]) &&
          line[i] != '(' &&
          line[i] != ')') {
        i++;
      }
      if (i == start) i++;
      final op = line.substring(start, i);
      add(start, i, HighlightToken.operator);
      // After a redirect comes a file name, not a command.
      commandPosition = !(op.contains('>') || op.contains('<'));
      continue;
    }

    // A word: quotes and $variables inside get their own colors.
    final start = i;
    final inner = <HighlightSpan>[];
    var equalsAt = -1;
    var quoted = false;
    while (i < n && !_isSpace(line[i]) && !_isOperatorChar(line[i])) {
      final ch = line[i];
      if (ch == r'\') {
        i += 2;
      } else if (ch == "'") {
        final q = i;
        i++;
        while (i < n && line[i] != "'") {
          i++;
        }
        if (i < n) i++;
        inner.add((start: q, end: i, token: HighlightToken.string));
        quoted = true;
      } else if (ch == '"') {
        final q = i;
        i++;
        var segment = q;
        while (i < n && line[i] != '"') {
          if (line[i] == r'\') {
            i += 2;
          } else if (line[i] == r'$') {
            inner.add((start: segment, end: i, token: HighlightToken.string));
            final v = i;
            i = _variableEnd(line, i);
            inner.add((start: v, end: i, token: HighlightToken.variable));
            segment = i;
          } else {
            i++;
          }
        }
        if (i < n) i++;
        inner.add((
          start: segment,
          end: i.clamp(0, n),
          token: HighlightToken.string,
        ));
        quoted = true;
      } else if (ch == r'$' && !(i + 1 < n && line[i + 1] == '(')) {
        final v = i;
        i = _variableEnd(line, i);
        inner.add((start: v, end: i, token: HighlightToken.variable));
      } else if (ch == r'$') {
        break; // $( starts a command substitution
      } else {
        if (ch == '=' && equalsAt < 0) equalsAt = i;
        i++;
      }
    }
    i = i.clamp(0, n);
    final word = line.substring(start, i);

    if (commandPosition &&
        equalsAt > start &&
        !quoted &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(word)) {
      // FOO=bar before a command: the name is a variable.
      add(start, equalsAt, HighlightToken.variable);
      spans.addAll(inner.where((s) => s.start > equalsAt));
      continue;
    }
    if (commandPosition) {
      final name = word.split('/').last;
      final base = name.contains('.') && name.startsWith('mkfs')
          ? 'mkfs'
          : name;
      final token = dangerousCommands.contains(base)
          ? HighlightToken.dangerous
          : HighlightToken.command;
      if (quoted) {
        spans.addAll(inner);
      } else {
        add(start, i, token);
      }
      // `sudo rm`: the next word is a command too.
      commandPosition = _prefixCommands.contains(base);
      continue;
    }
    if (word.startsWith('-') && !quoted) {
      add(start, i, HighlightToken.option);
    } else {
      spans.addAll(inner.where((s) => s.end > s.start));
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

/// End of the `$NAME`, `${...}` or `$?` starting at [i].
int _variableEnd(String line, int i) {
  final n = line.length;
  var j = i + 1;
  if (j < n && line[j] == '{') {
    while (j < n && line[j] != '}') {
      j++;
    }
    return (j + 1).clamp(0, n);
  }
  if (j < n && RegExp(r'[?#@*!$0-9-]').hasMatch(line[j])) return j + 1;
  while (j < n && RegExp(r'[A-Za-z0-9_]').hasMatch(line[j])) {
    j++;
  }
  return j;
}

/// Colors the command being typed at the shell prompt, right in the
/// terminal's cells - nothing is sent to or changed on the server.
///
/// It notes where typing starts (just after a prompt) and, after each
/// piece of output, recolors from there to the end of that line. Lines
/// the server already colors itself (zsh-syntax-highlighting, fish) are
/// left alone.
class CommandHighlighter {
  CommandHighlighter(this.terminal, this.settings);

  final Terminal terminal;
  final HighlightSettings Function() settings;

  /// The line and column where the command starts, while typing one.
  BufferLine? _line;
  int _column = 0;

  /// Our colors as cell values, to tell them apart from the server's.
  Set<int> _ours = {};

  /// Call with what the user types, before it's sent.
  void onInput(String data) {
    if (data.contains('\r') ||
        data.contains('\n') ||
        data.contains('\x03') ||
        data.contains('\x04')) {
      // The command is done (or abandoned); color what's there and stop.
      _recolor();
      _line = null;
      return;
    }
    if (_line != null || !settings().enabled || terminal.isUsingAltBuffer) {
      return;
    }
    final buffer = terminal.buffer;
    final line = buffer.lines[buffer.absoluteCursorY];
    final x = buffer.cursorX;
    if (!_afterPrompt(line.getText(0, x))) return;
    _line = line;
    _column = x;
  }

  /// Call after output was written to the terminal.
  void afterOutput() => _recolor();

  /// Forgets the line being typed (e.g. when the connection ends).
  void reset() => _line = null;

  static final _promptEnd = RegExp(r'[$#%>❯➜»\]]\s*$');

  /// Whether the text before the cursor looks like a shell prompt.
  static bool _afterPrompt(String before) =>
      before.trim().isNotEmpty && _promptEnd.hasMatch(before);

  void _recolor() {
    final start = _line;
    if (start == null) return;
    final s = settings();
    if (!s.enabled || terminal.isUsingAltBuffer || !start.attached) {
      _line = null;
      return;
    }
    final lines = terminal.mainBuffer.lines;
    final first = start.index;

    // The command: from the start column to the end of the line and the
    // lines it wraps onto.
    final cells = <(BufferLine, int)>[];
    final text = StringBuffer();
    var row = first;
    var x = _column;
    while (row < lines.length) {
      final line = lines[row];
      if (row > first && !line.isWrapped) break;
      for (; x < line.length; x++) {
        final w = line.getWidth(x);
        if (w == 0) continue; // second half of a wide character
        final cp = line.getCodePoint(x);
        cells.add((line, x));
        // One UTF-16 unit per cell keeps text and cells lined up.
        text.write(
          cp == 0 ? ' ' : (cp > 0xFFFF ? 'x' : String.fromCharCode(cp)),
        );
      }
      row++;
      x = 0;
    }

    // The cursor left this line (a completion list, a new prompt): stop.
    final cursorRow = terminal.mainBuffer.absoluteCursorY;
    if (cursorRow < first || cursorRow >= row) {
      _line = null;
      return;
    }

    _ours = {for (final c in s.colors.values) CellColor.rgb | (c & 0xFFFFFF)};
    for (final (line, cx) in cells) {
      final fg = line.getForeground(cx);
      if (fg != CellColor.normal && !_ours.contains(fg)) {
        // The server colors this line itself.
        _line = null;
        return;
      }
    }

    final str = text.toString();
    final colors = List<int>.filled(str.length, CellColor.normal);
    for (final span in highlightCommand(str)) {
      final color = s.colors[span.token] ?? defaultHighlightColors[span.token]!;
      for (var k = span.start; k < span.end && k < colors.length; k++) {
        colors[k] = CellColor.rgb | (color & 0xFFFFFF);
      }
    }
    for (var k = 0; k < cells.length; k++) {
      final (line, cx) = cells[k];
      if (line.getForeground(cx) != colors[k]) {
        line.setForeground(cx, colors[k]);
      }
    }
  }
}
