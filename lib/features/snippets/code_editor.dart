import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/terminal_theme.dart';
import 'code_syntax.dart';
import 'snippet.dart';

/// A [TextEditingController] that renders live syntax highlighting for a
/// [SnippetLanguage] while keeping text offsets 1-to-1 with the raw buffer.
class SyntaxHighlightingController extends TextEditingController {
  SyntaxHighlightingController({super.text, SnippetLanguage? language})
    : _language = language ?? SnippetLanguage.shell;

  SnippetLanguage _language;

  SnippetLanguage get language => _language;
  set language(SnippetLanguage value) {
    if (_language == value) return;
    _language = value;
    notifyListeners();
  }

  /// Spaces inserted per Tab key for the current language.
  int get tabSize => switch (_language) {
    SnippetLanguage.python || SnippetLanguage.powershell => 4,
    _ => 2,
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final palette = CodeSyntaxPalette.of(Theme.of(context).colorScheme);
    final base = (style ?? const TextStyle()).copyWith(color: palette.plain);
    final composing = value.composing;

    // While an IME is composing (e.g. Chinese Pinyin), render the composing
    // region underlined so IME candidates work seamlessly.
    if (withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length) {
      final before = text.substring(0, composing.start);
      final middle = text.substring(composing.start, composing.end);
      final after = text.substring(composing.end);
      return TextSpan(
        style: base,
        children: [
          if (before.isNotEmpty)
            buildHighlightedCodeSpan(
              source: before,
              language: _language,
              baseStyle: base,
              palette: palette,
            ),
          TextSpan(
            text: middle,
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
          if (after.isNotEmpty)
            buildHighlightedCodeSpan(
              source: after,
              language: _language,
              baseStyle: base,
              palette: palette,
            ),
        ],
      );
    }

    return buildHighlightedCodeSpan(
      source: text,
      language: _language,
      baseStyle: base,
      palette: palette,
    );
  }

  /// Inserts indentation spaces at the cursor (or indents selected lines).
  void indent({bool unindent = false}) {
    final sel = selection;
    if (!sel.isValid) return;
    final indentStr = ' ' * tabSize;
    final src = text;

    if (!unindent && sel.isCollapsed) {
      final next = src.replaceRange(sel.start, sel.end, indentStr);
      value = value.copyWith(
        text: next,
        selection: TextSelection.collapsed(offset: sel.start + tabSize),
        composing: TextRange.empty,
      );
      return;
    }

    // Line-wise indent / unindent for current line or multi-line selection.
    final lineStart = src.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    final blockStart = lineStart < 0 ? 0 : lineStart + 1;
    final blockEnd = sel.end;
    final block = src.substring(blockStart, blockEnd);
    final lines = block.split('\n');
    final out = <String>[];
    var firstDelta = 0;
    var totalDelta = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!unindent) {
        out.add('$indentStr$line');
        if (i == 0) firstDelta = tabSize;
        totalDelta += tabSize;
      } else {
        var remove = 0;
        while (remove < tabSize &&
            remove < line.length &&
            line.codeUnitAt(remove) == 0x20) {
          remove++;
        }
        if (remove == 0 && line.startsWith('\t')) remove = 1;
        out.add(line.substring(remove));
        if (i == 0) firstDelta = -remove;
        totalDelta -= remove;
      }
    }

    final replaced = out.join('\n');
    final next = src.replaceRange(blockStart, blockEnd, replaced);
    final nextBase = (sel.start + firstDelta).clamp(blockStart, next.length);
    final nextExtent = (sel.end + totalDelta).clamp(nextBase, next.length);
    value = value.copyWith(
      text: next,
      selection: sel.isCollapsed
          ? TextSelection.collapsed(offset: nextBase)
          : TextSelection(baseOffset: nextBase, extentOffset: nextExtent),
      composing: TextRange.empty,
    );
  }

  /// Inserts a newline while preserving (and optionally deepening) indentation.
  void insertNewlineWithAutoIndent() {
    final sel = selection;
    if (!sel.isValid) return;
    final src = text;
    final lineStartIdx = src.lastIndexOf(
      '\n',
      sel.start > 0 ? sel.start - 1 : 0,
    );
    final lineStart = lineStartIdx < 0 ? 0 : lineStartIdx + 1;
    final beforeCursor = src.substring(lineStart, sel.start);
    final leading = RegExp(r'^[ \t]*').stringMatch(beforeCursor) ?? '';
    final trimmed = beforeCursor.trimRight();

    var extra = '';
    if (_language == SnippetLanguage.python && trimmed.endsWith(':')) {
      extra = ' ' * tabSize;
    } else if (trimmed.endsWith('{') ||
        ((_language == SnippetLanguage.shell ||
                _language == SnippetLanguage.bash) &&
            RegExp(r'\b(?:then|do|else)\s*$').hasMatch(trimmed))) {
      extra = ' ' * tabSize;
    }

    final insert = '\n$leading$extra';
    final next = src.replaceRange(sel.start, sel.end, insert);
    value = value.copyWith(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + insert.length),
      composing: TextRange.empty,
    );
  }

  /// 1-based `(line, column)` of the current caret position.
  (int line, int column) get cursorPosition {
    final offset = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    var line = 1;
    var lastNewline = -1;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lastNewline = i;
      }
    }
    return (line, offset - lastNewline);
  }

  int get lineCount => '\n'.allMatches(text).length + 1;
}

/// VS Code-inspired code editor with synchronized line-number gutter, real-time
/// syntax highlighting, Tab/Shift+Tab indentation, auto-indent on Enter, and a
/// bottom status bar (`Ln`, `Col`, `Spaces`, `UTF-8`, `LF`, language).
class SnippetCodeEditor extends StatefulWidget {
  const SnippetCodeEditor({
    super.key,
    required this.controller,
    required this.languageLabel,
    required this.hintText,
    this.errorText,
    this.fieldKey,
    this.autofocus = false,
  });

  final SyntaxHighlightingController controller;
  final String languageLabel;
  final String hintText;
  final String? errorText;
  final Key? fieldKey;
  final bool autofocus;

  @override
  State<SnippetCodeEditor> createState() => _SnippetCodeEditorState();
}

class _SnippetCodeEditorState extends State<SnippetCodeEditor> {
  final _editorScroll = ScrollController();
  final _gutterScroll = ScrollController();
  final _focusNode = FocusNode();

  static const _fontSize = 13.5;
  static const _lineHeight = 1.55;
  static const _verticalPadding = 14.0;

  @override
  void initState() {
    super.initState();
    _editorScroll.addListener(_syncGutterScroll);
    widget.controller.addListener(_onTextOrSelectionChanged);
  }

  @override
  void didUpdateWidget(SnippetCodeEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTextOrSelectionChanged);
      widget.controller.addListener(_onTextOrSelectionChanged);
    }
  }

  @override
  void dispose() {
    _editorScroll.removeListener(_syncGutterScroll);
    widget.controller.removeListener(_onTextOrSelectionChanged);
    _editorScroll.dispose();
    _gutterScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncGutterScroll() {
    if (_gutterScroll.hasClients &&
        _gutterScroll.offset != _editorScroll.offset) {
      _gutterScroll.jumpTo(
        _editorScroll.offset.clamp(
          _gutterScroll.position.minScrollExtent,
          _gutterScroll.position.maxScrollExtent,
        ),
      );
    }
  }

  void _onTextOrSelectionChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never intercept while IME is composing (e.g. Enter/Tab in Pinyin).
    if (widget.controller.value.composing.isValid &&
        !widget.controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.controller.indent(unindent: kb.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.controller.insertNewlineWithAutoIndent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = CodeSyntaxPalette.of(scheme);
    final (activeLine, activeCol) = widget.controller.cursorPosition;
    final lineCount = widget.controller.lineCount;
    final rowHeight = _fontSize * _lineHeight;
    final gutterDigits = lineCount.toString().length.clamp(2, 5);
    final gutterWidth = 24.0 + gutterDigits * 9.0;

    final codeStyle = TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      fontSize: _fontSize,
      height: _lineHeight,
      color: palette.plain,
    );

    final selection = widget.controller.selection;
    final selectedChars = selection.isValid && !selection.isCollapsed
        ? (selection.end - selection.start).abs()
        : 0;

    return ColoredBox(
      key: const ValueKey('snippet-code-editor'),
      color: palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Line number gutter synced with the editor viewport.
                Container(
                  key: const ValueKey('snippet-editor-gutter'),
                  width: gutterWidth,
                  decoration: BoxDecoration(
                    color: palette.gutterBackground,
                    border: Border(
                      right: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: IgnorePointer(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _gutterScroll,
                        padding: const EdgeInsets.symmetric(
                          vertical: _verticalPadding,
                        ),
                        itemExtent: rowHeight,
                        itemCount: lineCount,
                        itemBuilder: (context, index) {
                          final n = index + 1;
                          final isCurrent = n == activeLine;
                          return Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 12),
                            color: isCurrent
                                ? palette.activeLineBackground
                                : null,
                            child: Text(
                              '$n',
                              style: codeStyle.copyWith(
                                color: isCurrent
                                    ? palette.activeLineNumber
                                    : palette.lineNumber,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // Editable syntax-highlighted code canvas.
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      key: widget.fieldKey,
                      controller: widget.controller,
                      focusNode: _focusNode,
                      scrollController: _editorScroll,
                      autofocus: widget.autofocus,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      style: codeStyle,
                      cursorColor: scheme.primary,
                      cursorWidth: 2,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: _verticalPadding,
                        ),
                        hintText: widget.hintText,
                        hintStyle: codeStyle.copyWith(
                          color: palette.lineNumber,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.errorText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: scheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errorText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // VS Code-style status bar at the bottom of the editor pane.
          Container(
            key: const ValueKey('snippet-editor-statusbar'),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.statusBarBackground,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: monoFontFamily,
                fontFamilyFallback: monoFontFallback,
              ),
              child: Row(
                children: [
                  Text('Ln $activeLine, Col $activeCol'),
                  if (selectedChars > 0) ...[
                    const SizedBox(width: 10),
                    Text('($selectedChars selected)'),
                  ],
                  const Spacer(),
                  Text('Spaces: ${widget.controller.tabSize}'),
                  const SizedBox(width: 14),
                  const Text('UTF-8'),
                  const SizedBox(width: 14),
                  const Text('LF'),
                  const SizedBox(width: 14),
                  Text(
                    widget.languageLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
