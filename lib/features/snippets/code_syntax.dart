import 'package:flutter/material.dart';

import 'snippet.dart';

/// Semantic token kinds produced by [tokenizeCode].
enum CodeTokenKind {
  plain,
  comment,
  keyword,
  builtin,
  string,
  number,
  variable,
  flag,
  operatorToken,
  functionName,
  decorator,
  placeholder,
}

class CodeToken {
  const CodeToken(this.text, this.kind);

  final String text;
  final CodeTokenKind kind;
}

/// VS Code-inspired syntax color palette tuned for light and dark themes.
class CodeSyntaxPalette {
  const CodeSyntaxPalette({
    required this.background,
    required this.gutterBackground,
    required this.statusBarBackground,
    required this.activeLineBackground,
    required this.lineNumber,
    required this.activeLineNumber,
    required this.plain,
    required this.comment,
    required this.keyword,
    required this.builtin,
    required this.string,
    required this.number,
    required this.variable,
    required this.flag,
    required this.operatorColor,
    required this.functionName,
    required this.decorator,
    required this.placeholderText,
    required this.placeholderBackground,
  });

  final Color background;
  final Color gutterBackground;
  final Color statusBarBackground;
  final Color activeLineBackground;
  final Color lineNumber;
  final Color activeLineNumber;
  final Color plain;
  final Color comment;
  final Color keyword;
  final Color builtin;
  final Color string;
  final Color number;
  final Color variable;
  final Color flag;
  final Color operatorColor;
  final Color functionName;
  final Color decorator;
  final Color placeholderText;
  final Color placeholderBackground;

  factory CodeSyntaxPalette.of(ColorScheme scheme) {
    if (scheme.brightness == Brightness.dark) {
      // VS Code Dark+ token palette on the app's terminal card background so
      // the selected editor browser tab joins seamlessly into the editor canvas.
      return CodeSyntaxPalette(
        background: scheme.surfaceContainerLowest,
        gutterBackground: scheme.surfaceContainerLowest,
        statusBarBackground: scheme.surfaceContainerLow,
        activeLineBackground: const Color(0x14FFFFFF),
        lineNumber: const Color(0xFF6E7681),
        activeLineNumber: const Color(0xFFC6C6C6),
        plain: const Color(0xFFD4D4D4),
        comment: const Color(0xFF6A9955),
        keyword: const Color(0xFFC586C0),
        builtin: const Color(0xFF4EC9B0),
        string: const Color(0xFFCE9178),
        number: const Color(0xFFB5CEA8),
        variable: const Color(0xFF9CDCFE),
        flag: const Color(0xFF569CD6),
        operatorColor: const Color(0xFFD4D4D4),
        functionName: const Color(0xFFDCDCAA),
        decorator: const Color(0xFFDCDCAA),
        placeholderText: scheme.onPrimaryContainer,
        placeholderBackground: scheme.primaryContainer.withValues(alpha: 0.85),
      );
    }
    // VS Code Light+ token palette on the app's light card surface.
    return CodeSyntaxPalette(
      background: scheme.surface,
      gutterBackground: scheme.surface,
      statusBarBackground: scheme.surfaceContainerLow,
      activeLineBackground: const Color(0x0D000000),
      lineNumber: const Color(0xFF8C8C8C),
      activeLineNumber: const Color(0xFF2B2B2B),
      plain: const Color(0xFF1F1F1F),
      comment: const Color(0xFF008000),
      keyword: const Color(0xFFAF00DB),
      builtin: const Color(0xFF267F99),
      string: const Color(0xFFA31515),
      number: const Color(0xFF098658),
      variable: const Color(0xFF001080),
      flag: const Color(0xFF0000FF),
      operatorColor: const Color(0xFF383A42),
      functionName: const Color(0xFF795E26),
      decorator: const Color(0xFF795E26),
      placeholderText: scheme.onPrimaryContainer,
      placeholderBackground: scheme.primaryContainer,
    );
  }

  TextStyle styleFor(CodeTokenKind kind, TextStyle base) => switch (kind) {
    CodeTokenKind.plain => base.copyWith(color: plain),
    CodeTokenKind.comment => base.copyWith(
      color: comment,
      fontStyle: FontStyle.italic,
    ),
    CodeTokenKind.keyword => base.copyWith(
      color: keyword,
      fontWeight: FontWeight.w600,
    ),
    CodeTokenKind.builtin => base.copyWith(color: builtin),
    CodeTokenKind.string => base.copyWith(color: string),
    CodeTokenKind.number => base.copyWith(color: number),
    CodeTokenKind.variable => base.copyWith(color: variable),
    CodeTokenKind.flag => base.copyWith(color: flag),
    CodeTokenKind.operatorToken => base.copyWith(color: operatorColor),
    CodeTokenKind.functionName => base.copyWith(color: functionName),
    CodeTokenKind.decorator => base.copyWith(color: decorator),
    CodeTokenKind.placeholder => base.copyWith(
      color: placeholderText,
      backgroundColor: placeholderBackground,
      fontWeight: FontWeight.w600,
    ),
  };
}

class _Rule {
  const _Rule(this.pattern, this.kind);

  final RegExp pattern;
  final CodeTokenKind kind;
}

final _placeholderRule = _Rule(
  RegExp(r'\{\{\s*[a-zA-Z0-9_.\-\u4e00-\u9fff]+\s*\}\}'),
  CodeTokenKind.placeholder,
);

final _shellRules = <_Rule>[
  _placeholderRule,
  // Shebang & line comments (only at start of line or after whitespace).
  _Rule(RegExp(r'#[^\n]*'), CodeTokenKind.comment),
  // Double-quoted, single-quoted, and backtick strings.
  _Rule(RegExp(r'"(?:\\.|[^"\\])*"'), CodeTokenKind.string),
  _Rule(RegExp(r"'[^']*'"), CodeTokenKind.string),
  _Rule(RegExp(r'`(?:\\.|[^`\\])*`'), CodeTokenKind.string),
  // Variables: ${VAR}, $VAR, $1, $?, $@, $#.
  _Rule(
    RegExp(r'\$\{[^}\n]*\}|\$(?:[A-Za-z_][A-Za-z0-9_]*|[0-9?*@#$\-!])'),
    CodeTokenKind.variable,
  ),
  // Shell keywords.
  _Rule(
    RegExp(
      r'\b(?:if|then|else|elif|fi|for|in|do|done|while|until|case|esac|select|'
      r'function|return|exit|break|continue|local|export|readonly|declare|'
      r'typeset|unset|shift|trap|set|source|eval|exec)\b',
    ),
    CodeTokenKind.keyword,
  ),
  // Common CLI / shell builtins.
  _Rule(
    RegExp(
      r'\b(?:echo|printf|read|cd|pwd|ls|cat|head|tail|grep|egrep|fgrep|awk|'
      r'sed|find|xargs|sort|uniq|wc|cut|tr|tee|mkdir|rmdir|rm|cp|mv|ln|chmod|'
      r'chown|tar|gzip|gunzip|zip|unzip|curl|wget|ssh|scp|rsync|ps|top|kill|'
      r'df|du|free|uname|uptime|whoami|id|date|sleep|test|true|false|sudo|'
      r'systemctl|service|journalctl|docker|kubectl|git|nginx|python3?|pip3?|'
      r'node|npm)\b',
    ),
    CodeTokenKind.builtin,
  ),
  // CLI flags like -la, --force, --output=foo.
  _Rule(
    RegExp(r'(?:(?<=\s)|^)--?[A-Za-z0-9][A-Za-z0-9_-]*'),
    CodeTokenKind.flag,
  ),
  // Numbers.
  _Rule(RegExp(r'\b\d+(?:\.\d+)?\b'), CodeTokenKind.number),
  // Operators / pipes / redirects.
  _Rule(RegExp(r'&&|\|\||<<-?|>>|[|;&<>]'), CodeTokenKind.operatorToken),
];

final _pythonRules = <_Rule>[
  _placeholderRule,
  // Triple-quoted strings first so they win over single quotes.
  _Rule(RegExp(r'[fFrRbBuU]{0,2}"""[\s\S]*?(?:"""|$)'), CodeTokenKind.string),
  _Rule(RegExp(r"[fFrRbBuU]{0,2}'''[\s\S]*?(?:'''|$)"), CodeTokenKind.string),
  // Line comments.
  _Rule(RegExp(r'#[^\n]*'), CodeTokenKind.comment),
  // Single and double quoted strings.
  _Rule(RegExp(r'[fFrRbBuU]{0,2}"(?:\\.|[^"\\\n])*"'), CodeTokenKind.string),
  _Rule(RegExp(r"[fFrRbBuU]{0,2}'(?:\\.|[^'\\\n])*'"), CodeTokenKind.string),
  // Decorators.
  _Rule(RegExp(r'@[A-Za-z_][A-Za-z0-9_.]*'), CodeTokenKind.decorator),
  // Python keywords.
  _Rule(
    RegExp(
      r'\b(?:False|None|True|and|as|assert|async|await|break|class|continue|'
      r'def|del|elif|else|except|finally|for|from|global|if|import|in|is|'
      r'lambda|match|case|nonlocal|not|or|pass|raise|return|try|while|with|'
      r'yield)\b',
    ),
    CodeTokenKind.keyword,
  ),
  // Built-in functions and types.
  _Rule(
    RegExp(
      r'\b(?:abs|all|any|bool|bytes|callable|chr|dict|dir|divmod|enumerate|'
      r'eval|exec|filter|float|format|frozenset|getattr|hasattr|hash|help|hex|'
      r'id|input|int|isinstance|issubclass|iter|len|list|map|max|min|next|'
      r'object|open|ord|pow|print|property|range|repr|reversed|round|set|'
      r'setattr|slice|sorted|staticmethod|classmethod|str|sum|super|tuple|'
      r'type|vars|zip|Exception|ValueError|TypeError|KeyError|OSError|'
      r'RuntimeError|self|cls)\b',
    ),
    CodeTokenKind.builtin,
  ),
  // Function calls / definitions: identifier followed by `(`.
  _Rule(
    RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()'),
    CodeTokenKind.functionName,
  ),
  // Numbers (hex, binary, float, int).
  _Rule(
    RegExp(r'\b(?:0[xXbBoO][0-9A-Fa-f_]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b'),
    CodeTokenKind.number,
  ),
];

final _powerShellRules = <_Rule>[
  _placeholderRule,
  // Block and line comments.
  _Rule(RegExp(r'<#[\s\S]*?(?:#>|$)'), CodeTokenKind.comment),
  _Rule(RegExp(r'#[^\n]*'), CodeTokenKind.comment),
  // Strings (including escaped quotes).
  _Rule(RegExp(r'"(?:`.|[^"`])*"'), CodeTokenKind.string),
  _Rule(RegExp(r"'(?:''|[^'])*'"), CodeTokenKind.string),
  // Variables: $var, $env:PATH, $_, ${foo}.
  _Rule(
    RegExp(r'\$\{[^}\n]*\}|\$(?:[A-Za-z0-9_]+:)?[A-Za-z0-9_]+'),
    CodeTokenKind.variable,
  ),
  // Keywords (case-insensitive in PowerShell).
  _Rule(
    RegExp(
      r'\b(?:begin|break|catch|class|continue|data|do|dynamicparam|else|'
      r'elseif|end|enum|exit|filter|finally|for|foreach|from|function|if|in|'
      r'param|process|return|switch|throw|trap|try|until|using|while)\b',
      caseSensitive: false,
    ),
    CodeTokenKind.keyword,
  ),
  // Cmdlets: Verb-Noun (e.g. Get-Process, Set-Location).
  _Rule(RegExp(r'\b[A-Z][A-Za-z]+-[A-Z][A-Za-z0-9]+\b'), CodeTokenKind.builtin),
  // Named parameters: -Path, -Force.
  _Rule(RegExp(r'(?:(?<=\s)|^)-[A-Za-z][A-Za-z0-9_]*'), CodeTokenKind.flag),
  // Numbers.
  _Rule(RegExp(r'\b\d+(?:\.\d+)?\b'), CodeTokenKind.number),
];

final _nodeRules = <_Rule>[
  _placeholderRule,
  // Block and line comments.
  _Rule(RegExp(r'/\*[\s\S]*?(?:\*/|$)'), CodeTokenKind.comment),
  _Rule(RegExp(r'//[^\n]*'), CodeTokenKind.comment),
  // Template literals & strings.
  _Rule(RegExp(r'`(?:\\.|[^`\\])*`'), CodeTokenKind.string),
  _Rule(RegExp(r'"(?:\\.|[^"\\\n])*"'), CodeTokenKind.string),
  _Rule(RegExp(r"'(?:\\.|[^'\\\n])*'"), CodeTokenKind.string),
  // JS keywords.
  _Rule(
    RegExp(
      r'\b(?:async|await|break|case|catch|class|const|continue|debugger|'
      r'default|delete|do|else|export|extends|false|finally|for|from|function|'
      r'if|import|in|instanceof|let|new|null|of|return|static|super|switch|'
      r'this|throw|true|try|typeof|undefined|var|void|while|with|yield)\b',
    ),
    CodeTokenKind.keyword,
  ),
  // Built-ins / globals.
  _Rule(
    RegExp(
      r'\b(?:console|process|Buffer|Promise|JSON|Math|Date|Array|Object|'
      r'String|Number|Boolean|Map|Set|RegExp|Error|URL|fetch|setTimeout|'
      r'setInterval|clearTimeout|clearInterval|require|module|exports)\b',
    ),
    CodeTokenKind.builtin,
  ),
  // Function calls.
  _Rule(
    RegExp(r'\b[A-Za-z_$][A-Za-z0-9_$]*(?=\s*\()'),
    CodeTokenKind.functionName,
  ),
  // Numbers.
  _Rule(
    RegExp(r'\b(?:0[xXbBoO][0-9A-Fa-f_]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b'),
    CodeTokenKind.number,
  ),
];

final _plainRules = <_Rule>[_placeholderRule];

List<_Rule> _rulesFor(SnippetLanguage language) => switch (language) {
  SnippetLanguage.shell || SnippetLanguage.bash => _shellRules,
  SnippetLanguage.python => _pythonRules,
  SnippetLanguage.powershell => _powerShellRules,
  SnippetLanguage.node => _nodeRules,
  SnippetLanguage.other => _plainRules,
};

/// Tokenizes [source] for [language] into contiguous spans covering the exact
/// original text (preserving every character and index for [TextEditingController]).
List<CodeToken> tokenizeCode(String source, SnippetLanguage language) {
  if (source.isEmpty) return const [];
  final rules = _rulesFor(language);
  final tokens = <CodeToken>[];
  var pos = 0;
  final plainBuf = StringBuffer();

  void flushPlain() {
    if (plainBuf.isNotEmpty) {
      tokens.add(CodeToken(plainBuf.toString(), CodeTokenKind.plain));
      plainBuf.clear();
    }
  }

  while (pos < source.length) {
    // Special guard for Shell comments: `#` only starts a comment at line start
    // or right after whitespace/operator (so `${#arr}` or `foo#bar` stays intact).
    Match? bestMatch;
    CodeTokenKind? bestKind;

    for (final rule in rules) {
      final m = rule.pattern.matchAsPrefix(source, pos);
      if (m == null || m.end == pos) continue;
      if (rule.kind == CodeTokenKind.comment &&
          (language == SnippetLanguage.shell ||
              language == SnippetLanguage.bash) &&
          pos > 0) {
        final prev = source.codeUnitAt(pos - 1);
        final startsComment =
            prev == 0x0A ||
            prev == 0x0D ||
            prev == 0x20 ||
            prev == 0x09 ||
            prev == 0x3B || // ;
            prev == 0x26 || // &
            prev == 0x7C || // |
            prev == 0x28; // (
        if (!startsComment) continue;
      }
      bestMatch = m;
      bestKind = rule.kind;
      break;
    }

    if (bestMatch != null && bestKind != null) {
      flushPlain();
      tokens.add(CodeToken(source.substring(pos, bestMatch.end), bestKind));
      pos = bestMatch.end;
    } else {
      plainBuf.writeCharCode(source.codeUnitAt(pos));
      pos++;
    }
  }
  flushPlain();
  return tokens;
}

/// Builds a highlighted [TextSpan] tree whose character offsets match [source]
/// 1-to-1 so cursor positioning and selection remain exact.
TextSpan buildHighlightedCodeSpan({
  required String source,
  required SnippetLanguage language,
  required TextStyle baseStyle,
  required CodeSyntaxPalette palette,
}) {
  final tokens = tokenizeCode(source, language);
  if (tokens.isEmpty) return TextSpan(style: baseStyle, text: source);
  return TextSpan(
    style: baseStyle,
    children: [
      for (final t in tokens)
        TextSpan(text: t.text, style: palette.styleFor(t.kind, baseStyle)),
    ],
  );
}
