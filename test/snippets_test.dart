import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/hosts/host_repository.dart';
import 'package:uessh/features/snippets/code_editor.dart';
import 'package:uessh/features/snippets/code_syntax.dart';
import 'package:uessh/features/snippets/snippet.dart';
import 'package:uessh/features/snippets/snippet_runner.dart';
import 'package:uessh/features/terminal/known_hosts.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';
import 'package:uessh/features/terminal/terminal_page.dart';
import 'package:uessh/features/terminal/terminal_session.dart';

import 'test_helpers.dart';

class _ConnectedFakeSession extends TerminalSession {
  _ConnectedFakeSession(Host host, TestEnv env)
    : super(
        host: host,
        repository: HostRepository(dataDir: env.dataDir, secrets: env.secrets),
        knownHosts: KnownHostsStore(dataDir: env.dataDir),
        prompts: FakePrompts(),
      ) {
    status = SessionStatus.connected;
  }

  @override
  Future<void> connect({bool auto = false}) async {
    status = SessionStatus.connected;
    notifyListeners();
  }
}

void main() {
  group('snippet model & repository', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    test(
      'saves and loads snippets with language, group, and description',
      () async {
        final repo = SnippetRepository(dataDir: env.dataDir);
        final items = [
          const Snippet(
            id: 's1',
            name: 'Disk check',
            language: SnippetLanguage.shell,
            content: 'df -h',
            group: 'Ops',
            description: 'Show mounted disks',
          ),
          const Snippet(
            id: 's2',
            name: 'Inspect JSON',
            language: SnippetLanguage.python,
            content: 'import json\nprint(json.dumps({"ok": True}))',
            group: 'Python',
          ),
        ];
        await repo.save(items);
        final loaded = await repo.load();
        expect(loaded.length, 2);
        expect(loaded[0].name, 'Disk check');
        expect(loaded[0].language, SnippetLanguage.shell);
        expect(loaded[0].group, 'Ops');
        expect(loaded[1].name, 'Inspect JSON');
        expect(loaded[1].language, SnippetLanguage.python);
        expect(loaded[1].content, contains('import json'));
      },
    );

    test('guesses language from script file extensions', () {
      expect(SnippetLanguage.fromFileName('deploy.sh'), SnippetLanguage.shell);
      expect(SnippetLanguage.fromFileName('setup.bash'), SnippetLanguage.bash);
      expect(
        SnippetLanguage.fromFileName('analyze.py'),
        SnippetLanguage.python,
      );
      expect(
        SnippetLanguage.fromFileName('clean.ps1'),
        SnippetLanguage.powershell,
      );
      expect(SnippetLanguage.fromFileName('script.js'), SnippetLanguage.node);
      expect(SnippetLanguage.fromFileName('notes.txt'), SnippetLanguage.other);
    });

    test('extracts unique placeholders in order and renders templates', () {
      const src = 'echo {{host}} {{port}} {{host}} {{目录}}';
      expect(extractPlaceholders(src), ['host', 'port', '目录']);
      expect(
        renderSnippetTemplate(src, {
          'host': 'web01',
          'port': '8080',
          '目录': '/tmp',
        }),
        'echo web01 8080 web01 /tmp',
      );
    });
  });

  group('snippet runner', () {
    test('runs single-line shell directly and wraps multi-line & scripts in heredoc', () {
      expect(
        buildSnippetExecutionInput(
          language: SnippetLanguage.shell,
          content: 'df -h',
        ),
        'df -h\r',
      );

      final multiSh = buildSnippetExecutionInput(
        language: SnippetLanguage.shell,
        content: 'set -e\r\necho hello\r\n',
      );
      expect(multiSh, startsWith(" sh -s <<'__UESSH_SNIPPET__'\r"));
      expect(multiSh, contains('set -e\recho hello\r__UESSH_SNIPPET__\r'));

      final py = buildSnippetExecutionInput(
        language: SnippetLanguage.python,
        content: 'import sys\nprint(sys.version)',
      );
      expect(
        py,
        " python3 - <<'__UESSH_SNIPPET__'\rimport sys\rprint(sys.version)\r__UESSH_SNIPPET__\r",
      );

      final bash = buildSnippetExecutionInput(
        language: SnippetLanguage.bash,
        content: 'echo hi',
      );
      expect(bash, startsWith(" bash -s <<'__UESSH_SNIPPET__'\r"));

      final node = buildSnippetExecutionInput(
        language: SnippetLanguage.node,
        content: 'console.log(1)',
      );
      expect(node, startsWith(" node - <<'__UESSH_SNIPPET__'\r"));
    });

    test('avoids heredoc delimiter collision when script contains marker', () {
      final py = buildSnippetExecutionInput(
        language: SnippetLanguage.python,
        content: 'print("__UESSH_SNIPPET__")\n__UESSH_SNIPPET__',
      );
      expect(py, startsWith(" python3 - <<'__UESSH_SNIPPET___1'\r"));
      expect(py, endsWith('\r__UESSH_SNIPPET___1\r'));
    });

    test('formats Windows PowerShell execution for python scripts', () {
      final ps = buildSnippetExecutionInput(
        language: SnippetLanguage.python,
        content: 'print("ok")',
        windowsPowerShell: true,
      );
      expect(ps, "@'\rprint(\"ok\")\r'@ | python -\r");
    });

    test('insert input omits trailing newline for review before running', () {
      expect(
        buildSnippetInsertInput(
          language: SnippetLanguage.shell,
          content: 'ls -la\n',
        ),
        'ls -la',
      );
      final pyInsert = buildSnippetInsertInput(
        language: SnippetLanguage.python,
        content: 'print(42)',
      );
      expect(pyInsert, startsWith(" python3 - <<'__UESSH_SNIPPET__'"));
      expect(pyInsert.endsWith('\r'), isFalse);
    });
  });

  group('syntax highlighting & code editor controller', () {
    test('tokenizes shell, python, powershell, and node preserving exact text', () {
      const sh =
          '#!/bin/sh\nif [ -f "\$HOME/a" ]; then\n  echo {{msg}} --force\nfi\n';
      final shTokens = tokenizeCode(sh, SnippetLanguage.shell);
      expect(shTokens.map((t) => t.text).join(), sh);
      expect(
        shTokens.any(
          (t) =>
              t.kind == CodeTokenKind.comment && t.text.startsWith('#!/bin/sh'),
        ),
        isTrue,
      );
      expect(
        shTokens.any((t) => t.kind == CodeTokenKind.keyword && t.text == 'if'),
        isTrue,
      );
      expect(
        shTokens.any(
          (t) => t.kind == CodeTokenKind.builtin && t.text == 'echo',
        ),
        isTrue,
      );
      expect(
        shTokens.any(
          (t) => t.kind == CodeTokenKind.placeholder && t.text == '{{msg}}',
        ),
        isTrue,
      );
      expect(
        shTokens.any(
          (t) => t.kind == CodeTokenKind.flag && t.text == '--force',
        ),
        isTrue,
      );

      const py =
          '@cache\ndef greet(name):\n    """doc"""\n    print(f"hi {name}", 42) # ok\n';
      final pyTokens = tokenizeCode(py, SnippetLanguage.python);
      expect(pyTokens.map((t) => t.text).join(), py);
      expect(
        pyTokens.any(
          (t) => t.kind == CodeTokenKind.decorator && t.text == '@cache',
        ),
        isTrue,
      );
      expect(
        pyTokens.any((t) => t.kind == CodeTokenKind.keyword && t.text == 'def'),
        isTrue,
      );
      expect(
        pyTokens.any(
          (t) => t.kind == CodeTokenKind.functionName && t.text == 'greet',
        ),
        isTrue,
      );
      expect(
        pyTokens.any(
          (t) => t.kind == CodeTokenKind.string && t.text == '"""doc"""',
        ),
        isTrue,
      );
      expect(
        pyTokens.any(
          (t) => t.kind == CodeTokenKind.builtin && t.text == 'print',
        ),
        isTrue,
      );
      expect(
        pyTokens.any((t) => t.kind == CodeTokenKind.number && t.text == '42'),
        isTrue,
      );
      expect(
        pyTokens.any(
          (t) => t.kind == CodeTokenKind.comment && t.text == '# ok',
        ),
        isTrue,
      );

      const ps = 'Get-Process -Name \$env:APP # check\n';
      final psTokens = tokenizeCode(ps, SnippetLanguage.powershell);
      expect(psTokens.map((t) => t.text).join(), ps);
      expect(
        psTokens.any(
          (t) => t.kind == CodeTokenKind.builtin && t.text == 'Get-Process',
        ),
        isTrue,
      );
      expect(
        psTokens.any(
          (t) => t.kind == CodeTokenKind.variable && t.text == r'$env:APP',
        ),
        isTrue,
      );

      const js = 'const x = await fetch(`ok`); // done\n';
      final jsTokens = tokenizeCode(js, SnippetLanguage.node);
      expect(jsTokens.map((t) => t.text).join(), js);
      expect(
        jsTokens.any(
          (t) => t.kind == CodeTokenKind.keyword && t.text == 'await',
        ),
        isTrue,
      );
      expect(
        jsTokens.any((t) => t.kind == CodeTokenKind.string && t.text == '`ok`'),
        isTrue,
      );
    });

    test('supports Tab/Shift+Tab indent, auto-indent on Enter, and cursor position', () {
      final ctrl = SyntaxHighlightingController(
        text: 'def main():',
        language: SnippetLanguage.python,
      );
      addTearDown(ctrl.dispose);
      ctrl.selection = const TextSelection.collapsed(offset: 11);
      expect(ctrl.cursorPosition, (1, 12));

      ctrl.insertNewlineWithAutoIndent();
      expect(ctrl.text, 'def main():\n    ');
      expect(ctrl.cursorPosition, (2, 5));

      ctrl.indent();
      expect(ctrl.text, 'def main():\n        ');
      ctrl.indent(unindent: true);
      expect(ctrl.text, 'def main():\n    ');
    });
  });

  group('snippets UI', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    testWidgets('create, filter, edit, and delete snippets on SnippetsPage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(overrides: env.overrides, child: const UesshApp()),
      );
      await settleIo(tester);

      await tester.tap(find.text('片段'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('还没有代码片段'), findsOneWidget);

      // Create a Python snippet in a new browser-style editor tab.
      expect(
        find.byKey(const ValueKey('editor-tabs-divider')),
        findsNothing,
        reason: 'no "|" separator before any editor tab is open',
      );
      await tester.tap(find.byKey(const ValueKey('new-snippet-button')));
      await tester.pumpAndSettle();

      // Editor opens in the top tab strip with a "|" separator on its left,
      // and flows into the rounded editor card below.
      final divider = find.byKey(const ValueKey('editor-tabs-divider'));
      final editorTab = find.byType(SnippetEditorBrowserTab);
      final plusBtn = find.byKey(const ValueKey('new-tab'));
      expect(divider, findsOneWidget);
      expect(editorTab, findsOneWidget);
      final plusRect = tester.getRect(plusBtn);
      final dividerRect = tester.getRect(divider);
      final tabRect = tester.getRect(editorTab);
      final cardRect = tester.getRect(
        find.byKey(const ValueKey('snippet-editor-card')),
      );
      expect(dividerRect.left, greaterThanOrEqualTo(plusRect.right));
      expect(tabRect.left, greaterThanOrEqualTo(dividerRect.right));
      expect(tabRect.bottom, cardRect.top);

      expect(
        find.byKey(const ValueKey('snippet-editor-window')),
        findsOneWidget,
      );
      final editorRect = tester.getRect(
        find.byKey(const ValueKey('snippet-code-editor')),
      );
      final infoRect = tester.getRect(
        find.byKey(const ValueKey('snippet-info-pane')),
      );
      expect(editorRect.right, lessThanOrEqualTo(infoRect.left));
      expect(
        find.byKey(const ValueKey('snippet-editor-gutter')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('snippet-editor-statusbar')),
        findsOneWidget,
      );

      // Import, Cancel, and Save buttons sit at the bottom of the right info pane.
      final infoPane = find.byKey(const ValueKey('snippet-info-pane'));
      final importBtn = find.byKey(const ValueKey('snippet-import-file'));
      final cancelBtn = find.byKey(const ValueKey('cancel-snippet'));
      final saveBtn = find.byKey(const ValueKey('save-snippet'));
      expect(
        find.descendant(of: infoPane, matching: importBtn),
        findsOneWidget,
      );
      expect(
        find.descendant(of: infoPane, matching: cancelBtn),
        findsOneWidget,
      );
      expect(find.descendant(of: infoPane, matching: saveBtn), findsOneWidget);
      final descRect = tester.getRect(
        find.byKey(const ValueKey('snippet-desc-field')),
      );
      final importRect = tester.getRect(importBtn);
      final cancelRect = tester.getRect(cancelBtn);
      final saveRect = tester.getRect(saveBtn);
      expect(importRect.top, greaterThan(descRect.bottom));
      expect(cancelRect.top, greaterThanOrEqualTo(importRect.bottom));
      expect(saveRect.top, greaterThanOrEqualTo(importRect.bottom));
      expect(cancelRect.left, greaterThanOrEqualTo(infoRect.left));
      expect(saveRect.right, lessThanOrEqualTo(infoRect.right));

      await tester.enterText(
        find.byKey(const ValueKey('snippet-name-field')),
        '检查端口',
      );
      await tester.tap(find.byKey(const ValueKey('snippet-language-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Python').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: editorTab, matching: find.text('检查端口.py')),
        findsOneWidget,
      );
      expect(find.text('Spaces: 4'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('snippet-group-field')),
        '运维',
      );
      await tester.enterText(
        find.byKey(const ValueKey('snippet-content-field')),
        'import socket\nprint("{{port}}")',
      );
      await tester.pump();
      expect(find.text('{{port}}'), findsOneWidget);

      await tester.tap(saveBtn);
      await settleIo(tester);
      await tester.pumpAndSettle();

      // Saving closes the editor tab and its "|" separator, returning to SnippetsPage.
      expect(find.byType(SnippetEditorBrowserTab), findsNothing);
      expect(find.byKey(const ValueKey('editor-tabs-divider')), findsNothing);
      expect(find.text('检查端口'), findsOneWidget);
      expect(find.text('PY'), findsOneWidget);
      expect(find.text('运维'), findsWidgets);

      // Create a Shell snippet so language filters appear.
      await tester.tap(find.byKey(const ValueKey('new-snippet-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('snippet-name-field')),
        '磁盘状态',
      );
      await tester.enterText(
        find.byKey(const ValueKey('snippet-content-field')),
        'df -h',
      );
      await tester.tap(find.byKey(const ValueKey('save-snippet')));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('磁盘状态'), findsOneWidget);
      expect(find.text('检查端口'), findsOneWidget);

      // Filter by Python chip.
      await tester.tap(find.widgetWithText(FilterChip, 'Python'));
      await tester.pumpAndSettle();
      expect(find.text('检查端口'), findsOneWidget);
      expect(find.text('磁盘状态'), findsNothing);

      // Reset to All and delete '检查端口'.
      await tester.tap(find.widgetWithText(FilterChip, '全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查端口'));
      await tester.pumpAndSettle();
      // Delete button is also inside the right info pane footer.
      expect(
        find.descendant(
          of: infoPane,
          matching: find.byKey(const ValueKey('delete-snippet')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('delete-snippet')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('检查端口'), findsNothing);
      expect(find.text('磁盘状态'), findsOneWidget);
    });

    testWidgets(
      'editor tabs coexist with SSH tabs behind "|" and preserve unsaved drafts',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...env.overrides,
              sessionFactoryProvider.overrideWithValue(
                (host) => _ConnectedFakeSession(host, env),
              ),
            ],
            child: const UesshApp(),
          ),
        );
        await settleIo(tester);

        // Open an SSH tab first.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(UesshApp)),
        );
        container
            .read(sessionsProvider.notifier)
            .open(
              const Host(
                id: 'srv1',
                label: 'prod-1',
                address: '10.0.0.1',
                port: 22,
                username: 'root',
                authMethod: AuthMethod.password,
              ),
            );
        await settleIo(tester);
        await tester.pumpAndSettle();

        // Open a new snippet editor tab from the terminal snippets panel.
        await tester.tap(find.byKey(const ValueKey('toggle-snippets-panel')));
        await settleIo(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('snippets-panel-add')));
        await tester.pumpAndSettle();

        // Strip layout: [Home] [SSH tab] [+] | [Editor tab]
        final sshRect = tester.getRect(find.byType(BrowserTab));
        final plusRect = tester.getRect(find.byKey(const ValueKey('new-tab')));
        final dividerRect = tester.getRect(
          find.byKey(const ValueKey('editor-tabs-divider')),
        );
        final editorTabRect = tester.getRect(
          find.byType(SnippetEditorBrowserTab),
        );
        expect(plusRect.left, greaterThanOrEqualTo(sshRect.right));
        expect(dividerRect.left, greaterThanOrEqualTo(plusRect.right));
        expect(editorTabRect.left, greaterThanOrEqualTo(dividerRect.right));

        // Type unsaved draft code.
        await tester.enterText(
          find.byKey(const ValueKey('snippet-name-field')),
          'backup',
        );
        await tester.enterText(
          find.byKey(const ValueKey('snippet-content-field')),
          'tar -czf out.tgz /data',
        );
        await tester.pump();
        expect(find.text('backup.sh'), findsOneWidget);

        // Switch back to the SSH tab, then return to the editor tab: draft stays intact.
        await tester.tap(find.byType(BrowserTab));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('snippet-editor-card')), findsNothing);
        expect(find.byKey(const ValueKey('terminal-card')), findsOneWidget);

        await tester.tap(find.byType(SnippetEditorBrowserTab));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('snippet-editor-card')),
          findsOneWidget,
        );
        final contentField = tester.widget<TextField>(
          find.byKey(const ValueKey('snippet-content-field')),
        );
        expect(contentField.controller?.text, 'tar -czf out.tgz /data');

        // Clicking Cancel on a dirty tab asks to discard changes.
        await tester.tap(find.byKey(const ValueKey('cancel-snippet')));
        await tester.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsOneWidget);

        // Keep editing keeps the tab open.
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.byType(SnippetEditorBrowserTab), findsOneWidget);

        // Confirming discard closes the editor tab and returns to the SSH tab.
        await tester.tap(find.byKey(const ValueKey('cancel-snippet')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();
        expect(find.byType(SnippetEditorBrowserTab), findsNothing);
        expect(find.byKey(const ValueKey('editor-tabs-divider')), findsNothing);
        expect(find.byKey(const ValueKey('terminal-card')), findsOneWidget);
      },
    );

    testWidgets(
      'run python snippet with placeholder from terminal side panel',
      (tester) async {
        final repo = SnippetRepository(dataDir: env.dataDir);
        await tester.runAsync(
          () => repo.save(const [
            Snippet(
              id: 'py1',
              name: '列目录脚本',
              language: SnippetLanguage.python,
              content: 'import os\nprint(os.listdir("{{dir}}"))',
            ),
          ]),
        );

        late _ConnectedFakeSession session;
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...env.overrides,
              sessionFactoryProvider.overrideWithValue(
                (host) => session = _ConnectedFakeSession(host, env),
              ),
            ],
            child: const UesshApp(),
          ),
        );
        await settleIo(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(UesshApp)),
        );
        container
            .read(sessionsProvider.notifier)
            .open(
              const Host(
                id: 'srv',
                label: 'srv',
                address: '10.0.0.1',
                port: 22,
                username: 'root',
                authMethod: AuthMethod.password,
              ),
            );
        await settleIo(tester);
        await tester.pumpAndSettle();

        final sent = <String>[];
        session.debugOnSend = sent.add;

        // Open the snippets side panel from the terminal's side rail.
        await tester.tap(find.byKey(const ValueKey('toggle-snippets-panel')));
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('snippets-panel')), findsOneWidget);
        expect(find.text('列目录脚本'), findsOneWidget);

        // Tap Run -> fill {{dir}} -> executes heredoc python3 script.
        await tester.tap(find.byKey(const ValueKey('panel-snippet-run-py1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('snippet-vars-dialog')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('snippet-var-dir')),
          '/var/log',
        );
        await tester.tap(find.byKey(const ValueKey('snippet-vars-submit')));
        await tester.pumpAndSettle();

        expect(sent.length, 1);
        expect(sent.single, startsWith(" python3 - <<'__UESSH_SNIPPET__'\r"));
        expect(sent.single, contains('os.listdir("/var/log")'));
      },
    );
  });
}
