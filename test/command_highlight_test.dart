import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/settings/app_settings.dart';
import 'package:uessh/features/terminal/command_highlight.dart';
import 'package:xterm2/xterm.dart';

import 'test_helpers.dart';

/// "word:token" for each colored span.
List<String> tokens(String line) => [
  for (final s in highlightCommand(line))
    '${line.substring(s.start, s.end)}:${s.token.name}',
];

void main() {
  group('highlightCommand', () {
    test('command, options, plain arguments', () {
      expect(tokens('ls -la /tmp'), ['ls:command', '-la:option']);
    });

    test('dangerous commands, also after sudo and with a path', () {
      expect(tokens('sudo rm -rf x'), [
        'sudo:command',
        'rm:dangerous',
        '-rf:option',
      ]);
      expect(tokens('/bin/rm a'), ['/bin/rm:dangerous']);
      expect(tokens('mkfs.ext4 /dev/sdb'), ['mkfs.ext4:dangerous']);
      expect(tokens('echo rm'), ['echo:command']);
    });

    test('pipes and && start a new command; redirects take a file', () {
      expect(tokens('cat a | grep b && rm c > out'), [
        'cat:command',
        '|:operator',
        'grep:command',
        '&&:operator',
        'rm:dangerous',
        '>:operator',
      ]);
      expect(tokens(r'echo $(whoami)'), [
        'echo:command',
        r'$(:operator',
        'whoami:command',
        '):operator',
      ]);
    });

    test('strings, variables and comments', () {
      expect(tokens(r'''echo 'a b' "x $HOME y" $USER ${P} $? # note'''), [
        'echo:command',
        "'a b':string",
        '"x :string',
        r'$HOME:variable',
        ' y":string',
        r'$USER:variable',
        r'${P}:variable',
        r'$?:variable',
        '# note:comment',
      ]);
      // # inside a word isn't a comment.
      expect(tokens('echo a#b'), ['echo:command']);
    });

    test('FOO=bar before a command', () {
      expect(tokens('LANG=C sort f'), ['LANG:variable', 'sort:command']);
    });

    test('unfinished input does not throw', () {
      for (final s in [
        '"abc',
        "'abc",
        r'${x',
        r'echo \',
        r'$',
        '|',
        r'echo "$',
      ]) {
        expect(() => highlightCommand(s), returnsNormally, reason: s);
      }
    });
  });

  group('CommandHighlighter', () {
    late Terminal terminal;
    late CommandHighlighter h;
    var enabled = true;
    final colors = const AppSettings().highlight.colors;
    int rgb(HighlightToken t) => CellColor.rgb | (colors[t]! & 0xFFFFFF);

    setUp(() {
      enabled = true;
      terminal = Terminal();
      h = CommandHighlighter(
        terminal,
        () => (enabled: enabled, colors: colors),
      );
    });

    /// Types [text] like a shell with echo: input first, then its echo.
    void type(String text) {
      for (final ch in text.split('')) {
        h.onInput(ch);
        terminal.write(ch);
        h.afterOutput();
      }
    }

    int fg(int x) =>
        terminal.buffer.lines[terminal.buffer.absoluteCursorY].getForeground(x);

    test('colors the typed command after a prompt', () {
      terminal.write(r'user@host:~$ ');
      type('rm -rf /x');
      const p = 13; // prompt length
      expect(fg(p), rgb(HighlightToken.dangerous));
      expect(fg(p + 1), rgb(HighlightToken.dangerous));
      expect(fg(p + 3), rgb(HighlightToken.option));
      expect(fg(p + 7), CellColor.normal); // the path
      expect(fg(0), CellColor.normal); // the prompt untouched
    });

    test('a word changes color as it changes meaning', () {
      terminal.write(r'$ ');
      type('ls');
      expect(fg(2), rgb(HighlightToken.command));
      type(' x');
      expect(fg(5), CellColor.normal);
    });

    test('nothing without a prompt before the cursor', () {
      terminal.write('Enter name: ');
      type('rm');
      expect(fg(12), CellColor.normal);
    });

    test('off: nothing is colored', () {
      enabled = false;
      terminal.write(r'$ ');
      type('ls');
      expect(fg(2), CellColor.normal);
    });

    test('lines the server colors itself are left alone', () {
      terminal.write(r'$ ');
      h.onInput('l');
      terminal.write('\x1b[31ml\x1b[0m');
      h.afterOutput();
      h.onInput('s');
      terminal.write('\x1b[31ms\x1b[0m');
      h.afterOutput();
      expect(fg(2), isNot(rgb(HighlightToken.command)));
    });

    test('stops at Enter; command output is not colored', () {
      terminal.write(r'$ ');
      type('ls');
      h.onInput('\r');
      terminal.write('\r\nrm file\r\n');
      h.afterOutput();
      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY - 1];
      expect(line.getText().trim(), 'rm file');
      expect(line.getForeground(0), CellColor.normal);
    });

    test('long commands that wrap are colored on every row', () {
      terminal.resize(20, 10);
      terminal.write(r'$ ');
      type('echo ${'a' * 20} --flag');
      final row = terminal.buffer.absoluteCursorY;
      final line = terminal.buffer.lines[row];
      expect(line.isWrapped, isTrue);
      final at = line.getText().indexOf('--flag');
      expect(line.getForeground(at), rgb(HighlightToken.option));
    });
  });

  test('settings: colors round-trip; defaults are not stored', () {
    final s = const AppSettings().copyWith(
      syntaxHighlight: false,
      highlightColors: {HighlightToken.command: 0xFF112233},
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.syntaxHighlight, isFalse);
    expect(back.highlightColor(HighlightToken.command), 0xFF112233);
    expect(
      back.highlightColor(HighlightToken.option),
      defaultHighlightColors[HighlightToken.option],
    );
    expect(
      const AppSettings().toJson().containsKey('highlightColors'),
      isFalse,
    );
    // Junk in the file is ignored.
    final junk = AppSettings.fromJson({
      'highlightColors': {'nope': 1, 'command': 'red'},
      'reconnectAttempts': -4,
    });
    expect(junk.highlightColors, isEmpty);
    expect(junk.reconnectAttempts, 1);
  });

  testWidgets('settings page: pick a color, turn reconnect off', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('highlight-command'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('highlight-preview')), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-ffff7eb6')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('highlight-reset')), findsOneWidget);

    final reconnect = find.byKey(const ValueKey('auto-reconnect'));
    await tester.ensureVisible(reconnect);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reconnect-attempts')), findsOneWidget);
    await tester.tap(reconnect);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reconnect-attempts')), findsNothing);
    await settleIo(tester);

    final saved = (await tester.runAsync(
      () => SettingsStore(dataDir: env.dataDir).load(),
    ))!;
    expect(saved.highlightColor(HighlightToken.command), 0xFFFF7EB6);
    expect(saved.autoReconnect, isFalse);
    expect(saved.reconnectAttempts, 3);
    expect(saved.reconnectDelaySeconds, 3);
  });
}
