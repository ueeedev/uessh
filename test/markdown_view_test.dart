import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/ai/markdown_view.dart';
import 'package:uessh/l10n/generated/app_localizations.dart';

void main() {
  final codes = <(String, String)>[];

  Future<void> show(WidgetTester tester, String text) async {
    codes.clear();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownView(
              text: text,
              codeBlock: (lang, code) {
                codes.add((lang, code));
                return Text('CODE[$lang]:$code');
              },
            ),
          ),
        ),
      ),
    );
  }

  Finder rich(String s) => find.text(s, findRichText: true);

  /// The style of the span holding [text] inside the RichText showing it.
  TextStyle? styleOf(WidgetTester tester, String text) {
    TextStyle? found;
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      w.text.visitChildren((span) {
        if (span is TextSpan && span.text == text) found = span.style;
        return found == null;
      });
      if (found != null) break;
    }
    return found;
  }

  testWidgets('tables: header, cells, alignment, <br> in a cell', (
    tester,
  ) async {
    await show(tester, '''
| 名称 | 大小 | 说明 |
| :--- | ---: | :---: |
| vda1 | 1M | a<br>b |
| vda3 | 49.8G | **根分区** |
''');
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(3));
    expect(table.children.first.children, hasLength(3));
    expect(rich('名称'), findsOneWidget);
    expect(rich('49.8G'), findsOneWidget);
    expect(rich('a\nb'), findsOneWidget);
    expect(rich('根分区'), findsOneWidget);
    expect(find.text('|', findRichText: true), findsNothing);
    final size = tester.widget<RichText>(rich('49.8G'));
    expect(size.textAlign, TextAlign.right);
    expect(styleOf(tester, '根分区')?.fontWeight, FontWeight.w600);
  });

  testWidgets('lists: bullets, numbers from start, nested, tasks', (
    tester,
  ) async {
    await show(tester, '''
- one
- two
  - inner

3. third
4. fourth

- [x] done
- [ ] todo
''');
    expect(rich('one'), findsOneWidget);
    expect(rich('inner'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(3));
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
    expect(rich('done'), findsOneWidget);
    expect(find.textContaining('[x]', findRichText: true), findsNothing);
  });

  testWidgets('headings, quotes, rules and inline styles', (tester) async {
    await show(tester, '''
## 磁盘

> 注意：*不要* 删除 ~~这个~~ 分区

---

用 `df -h` 查看。
''');
    expect(rich('磁盘'), findsOneWidget);
    expect(find.textContaining('##', findRichText: true), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    expect(styleOf(tester, '不要')?.fontStyle, FontStyle.italic);
    expect(styleOf(tester, '这个')?.decoration, TextDecoration.lineThrough);
    expect(styleOf(tester, 'df -h')?.fontFamily, isNotNull);
    // Quote text is dimmed.
    final quote = tester.widget<RichText>(
      find.textContaining('注意', findRichText: true),
    );
    final scheme = Theme.of(tester.element(find.byType(MarkdownView)))
        .colorScheme;
    // Text.rich wraps our span in the default style: look inside.
    final inner = (quote.text as TextSpan).children!.first as TextSpan;
    expect(inner.style?.color, scheme.onSurfaceVariant);
  });

  testWidgets('code blocks go to the builder; unfinished ones too', (
    tester,
  ) async {
    await show(tester, 'Run:\n\n```bash\nls -la\n```\n\nThen:\n\n```\nfree');
    expect(codes, [('bash', 'ls -la'), ('', 'free')]);
  });

  testWidgets('links ask before opening; other schemes do nothing', (
    tester,
  ) async {
    await show(
      tester,
      '[文档](https://example.com/a) and [x](file:///etc/passwd)',
    );
    await tester.tapOnText(find.textRange.ofSubstring('文档'));
    await tester.pumpAndSettle();
    expect(find.text('打开这个链接？'), findsOneWidget);
    expect(find.text('https://example.com/a'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('x'));
    await tester.pumpAndSettle();
    expect(find.text('打开这个链接？'), findsNothing);
  });

  testWidgets('html and images are shown as text, not loaded', (tester) async {
    await show(tester, '<script>alert(1)</script>\n\n![logo](https://x/y.png)');
    expect(find.textContaining('<script>', findRichText: true), findsOneWidget);
    expect(rich('[logo]'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
