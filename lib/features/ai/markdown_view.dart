import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/open_url.dart';
import '../../l10n/l10n.dart';
import '../../theme/terminal_theme.dart';

/// Builds a fenced code block (language may be empty).
typedef CodeBlockBuilder = Widget Function(String language, String code);

/// Parses [text] as GitHub-flavored Markdown into nodes.
List<md.Node> parseMarkdown(String text) {
  final doc = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  return doc.parseLines(text.replaceAll('\r\n', '\n').split('\n'));
}

/// Shows Markdown from an AI reply: headings, paragraphs, lists (also
/// task lists), quotes, tables, rules, code blocks and inline styles.
///
/// The text comes from an AI service, so it's treated as untrusted:
/// raw HTML is shown as plain text, images as their description, and
/// links open only after the user confirms the address.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.text, required this.codeBlock});

  final String text;
  final CodeBlockBuilder codeBlock;

  @override
  Widget build(BuildContext context) {
    final r = _Renderer(context, codeBlock);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: r.blocks(parseMarkdown(text)),
    );
  }
}

class _Renderer {
  _Renderer(this.context, this.codeBlock, {TextStyle? base})
    : theme = Theme.of(context),
      base = base ?? Theme.of(context).textTheme.bodyMedium!;

  final BuildContext context;
  final CodeBlockBuilder codeBlock;
  final ThemeData theme;
  final TextStyle base;

  ColorScheme get scheme => theme.colorScheme;

  static const _gap = 8.0;

  // --- Blocks ---

  List<Widget> blocks(List<md.Node> nodes) {
    final out = <Widget>[];
    for (final n in nodes) {
      final w = block(n);
      if (w == null) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: _gap));
      out.add(w);
    }
    return out;
  }

  Widget? block(md.Node node) {
    if (node is md.Text) {
      // Raw HTML blocks and the like: plain text.
      final t = node.text.trim();
      return t.isEmpty ? null : _text([TextSpan(text: t)]);
    }
    if (node is! md.Element) return null;
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        final size = switch (level) {
          1 => 20.0,
          2 => 18.0,
          3 => 16.0,
          _ => 15.0,
        };
        return Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 4 : 0),
          child: _text(
            inlines(node.children),
            style: base.copyWith(fontSize: size, fontWeight: FontWeight.w600),
          ),
        );
      case 'p':
        return _text(inlines(node.children));
      case 'pre':
        return _code(node);
      case 'hr':
        return Divider(height: 8, color: scheme.outlineVariant);
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.outlineVariant, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _Renderer(
              context,
              codeBlock,
              base: base.copyWith(color: scheme.onSurfaceVariant),
            ).blocks(node.children ?? const []),
          ),
        );
      case 'ul' || 'ol':
        return _list(node);
      case 'table':
        return _table(node);
      default:
        // Anything else (e.g. inline content at the top level).
        final spans = inlines([node]);
        return spans.isEmpty ? null : _text(spans);
    }
  }

  Widget _code(md.Element pre) {
    final child = pre.children?.firstOrNull;
    var language = '';
    var code = pre.textContent;
    if (child is md.Element && child.tag == 'code') {
      final cls = child.attributes['class'] ?? '';
      if (cls.startsWith('language-')) language = cls.substring(9);
      code = child.textContent;
    }
    return codeBlock(language, code.replaceAll(RegExp(r'\n+$'), ''));
  }

  Widget _list(md.Element list) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final c in list.children ?? const <md.Node>[])
        if (c is md.Element && c.tag == 'li') c,
    ];
    final markerStyle = base.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ordered ? 26 : 18,
                  child: _marker(items[i], ordered, start + i, markerStyle),
                ),
                Expanded(child: _listItem(items[i])),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(md.Element li, bool ordered, int n, TextStyle style) {
    final box = _taskBox(li);
    if (box != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(
          box ? Icons.check_box : Icons.check_box_outline_blank,
          size: 16,
          color: box ? scheme.primary : scheme.onSurfaceVariant,
        ),
      );
    }
    return Text(ordered ? '$n.' : '•', style: style);
  }

  /// Checked state of a task list item (`- [x] done`), or null.
  bool? _taskBox(md.Element li) {
    for (final c in li.children ?? const <md.Node>[]) {
      final input = c is md.Element && c.tag == 'p'
          ? c.children?.firstOrNull
          : c;
      if (input is md.Element && input.tag == 'input') {
        return input.attributes.containsKey('checked');
      }
    }
    return null;
  }

  /// An item holds either inline content or blocks (paragraphs, nested
  /// lists, code).
  Widget _listItem(md.Element li) {
    final children = li.children ?? const <md.Node>[];
    final isBlock = children.any(
      (c) =>
          c is md.Element &&
          const {
            'p',
            'ul',
            'ol',
            'pre',
            'blockquote',
            'table',
            'hr',
            'h1',
            'h2',
            'h3',
            'h4',
            'h5',
            'h6',
          }.contains(c.tag),
    );
    if (!isBlock) return _text(inlines(children));
    // Inline runs between blocks (e.g. "text" then a nested list).
    final parts = <Widget>[];
    var run = <md.Node>[];
    void flush() {
      final spans = inlines(run);
      if (spans.isNotEmpty) parts.add(_text(spans));
      run = [];
    }

    for (final c in children) {
      if (c is md.Element &&
          (c.tag == 'p' ||
              c.tag == 'ul' ||
              c.tag == 'ol' ||
              c.tag == 'pre' ||
              c.tag == 'blockquote' ||
              c.tag == 'table' ||
              c.tag == 'hr' ||
              c.tag.startsWith('h'))) {
        flush();
        final w = block(c);
        if (w != null) parts.add(w);
      } else {
        run.add(c);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
            child: parts[i],
          ),
      ],
    );
  }

  Widget _table(md.Element table) {
    final rows = <(bool header, List<md.Element> cells)>[];
    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        rows.add((
          section.tag == 'thead',
          [
            for (final c in tr.children ?? const <md.Node>[])
              if (c is md.Element && (c.tag == 'th' || c.tag == 'td')) c,
          ],
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((r) => r.$2.length)
        .reduce((a, b) => a > b ? a : b);
    final border = BorderSide(color: scheme.outlineVariant);

    TextAlign alignOf(md.Element cell) {
      final a = cell.attributes['align'] ?? cell.attributes['style'] ?? '';
      if (a.contains('center')) return TextAlign.center;
      if (a.contains('right')) return TextAlign.right;
      return TextAlign.left;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SingleChildScrollView(
        key: const ValueKey('md-table'),
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            top: border,
            bottom: border,
            left: border,
            right: border,
            horizontalInside: border,
            verticalInside: border,
            borderRadius: BorderRadius.circular(8),
          ),
          children: [
            for (final (header, cells) in rows)
              TableRow(
                decoration: header
                    ? BoxDecoration(color: scheme.surfaceContainerHighest)
                    : null,
                children: [
                  for (var c = 0; c < columns; c++)
                    ConstrainedBox(
                      // Long cells wrap instead of making the table huge.
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: c < cells.length
                            ? _text(
                                inlines(cells[c].children),
                                style: header
                                    ? base.copyWith(fontWeight: FontWeight.w600)
                                    : null,
                                align: alignOf(cells[c]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _text(List<InlineSpan> spans, {TextStyle? style, TextAlign? align}) =>
      Text.rich(
        TextSpan(style: style ?? base, children: spans),
        textAlign: align ?? TextAlign.start,
      );

  // --- Inline ---

  List<InlineSpan> inlines(List<md.Node>? nodes, [TextStyle? style]) {
    final out = <InlineSpan>[];
    for (final n in nodes ?? const <md.Node>[]) {
      out.addAll(inline(n, style));
    }
    return out;
  }

  List<InlineSpan> inline(md.Node node, TextStyle? style) {
    if (node is md.Text) {
      // Inline HTML is shown as text, except line breaks (common in table
      // cells).
      final text = node.text.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false),
        '\n',
      );
      return [TextSpan(text: text, style: style)];
    }
    if (node is! md.Element) return const [];
    final s = style ?? const TextStyle();
    switch (node.tag) {
      case 'strong':
        return inlines(node.children, s.copyWith(fontWeight: FontWeight.w600));
      case 'em':
        return inlines(node.children, s.copyWith(fontStyle: FontStyle.italic));
      case 'del':
        return inlines(
          node.children,
          s.copyWith(decoration: TextDecoration.lineThrough),
        );
      case 'code':
        return [
          TextSpan(
            text: node.textContent,
            style: s.copyWith(
              fontFamily: monoFontFamily,
              fontFamilyFallback: monoFontFallback,
              fontSize: (base.fontSize ?? 14) - 1,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ];
      case 'br':
        return const [TextSpan(text: '\n')];
      case 'img':
        // Not loaded: an AI reply shouldn't fetch things by itself.
        final alt = node.attributes['alt'] ?? '';
        return [
          TextSpan(
            text: '[${alt.isEmpty ? 'image' : alt}]',
            style: s.copyWith(color: scheme.onSurfaceVariant),
          ),
        ];
      case 'a':
        final href = node.attributes['href'] ?? '';
        final linkStyle = s.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary,
        );
        final recognizer = TapGestureRecognizer()
          ..onTap = () => openLink(context, href);
        return [
          for (final span in inlines(node.children, linkStyle))
            if (span is TextSpan)
              TextSpan(
                text: span.text,
                style: span.style,
                recognizer: recognizer,
                mouseCursor: SystemMouseCursors.click,
              )
            else
              span,
        ];
      case 'input':
        return const []; // task list box: drawn as the item's marker
      default:
        return inlines(node.children, style);
    }
  }
}

/// Opens [href] in the browser after the user confirms the address
/// (link text in an AI reply can say anything). Only http(s).
Future<void> openLink(BuildContext context, String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return;
  }
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.aiOpenLinkTitle),
      content: SelectableText(uri.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('open-link'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.aiOpenLink),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await openInBrowser(uri.toString());
}
