import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/ai/ai_config.dart';
import 'package:uessh/features/ai/ai_history.dart';
import 'package:uessh/features/hosts/host.dart';
import 'package:uessh/features/terminal/sessions_providers.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(UesshApp)));
    // Load the AI settings outside the fake clock (the settings card that
    // used to load them at start is now built only when scrolled to).
    await tester.runAsync(() => c.read(aiConfigProvider.future));
    await tester.pump();
    return c;
  }

  /// Opens a terminal tab (port 1: refused at once, so it settles).
  Future<void> openTab(WidgetTester tester, ProviderContainer c) async {
    c
        .read(sessionsProvider.notifier)
        .open(
          const Host(
            id: 'h',
            label: 'web-01',
            address: '127.0.0.1',
            port: 1,
            username: 'root',
            authMethod: AuthMethod.password,
          ),
        );
    await tester.pump(); // opening a session shows its tab
    await settleIo(tester);
    await tester.pumpAndSettle();
  }

  Future<void> configureAnthropic(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    await tester.runAsync(() async {
      await c.read(aiConfigProvider.future);
      await c
          .read(aiConfigProvider.notifier)
          .saveProvider(
            AiProvider.builtIn(AiVendor.anthropic),
            apiKey: 'sk-ant-test',
          );
    });
    await settleIo(tester);
    await tester.pumpAndSettle();
  }

  final aiPanel = find.byKey(const ValueKey('ai-panel'));

  testWidgets('AI button opens the AI panel; buttons switch and close', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await openTab(tester, c);
    expect(aiPanel, findsNothing);

    await tester.tap(find.byKey(const ValueKey('toggle-ai-panel')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(aiPanel, findsOneWidget);
    // The buttons are a rail on the right edge, AI on top, below the tabs.
    final ai = tester.getCenter(find.byKey(const ValueKey('toggle-ai-panel')));
    final info = tester.getCenter(
      find.byKey(const ValueKey('toggle-info-panel')),
    );
    final rail = tester.getRect(find.byKey(const ValueKey('side-rail')));
    final strip = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    expect(ai.dy, lessThan(info.dy));
    expect(ai.dx, info.dx);
    expect(rail.right, 1400);
    expect(rail.top, greaterThanOrEqualTo(strip.bottom));
    // The panel opens left of the rail.
    expect(tester.getRect(aiPanel).right, lessThanOrEqualTo(rail.left));
    // No provider yet: points to Settings.
    expect(find.text('还没有配置 AI 供应商'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-info-panel')));
    await tester.pumpAndSettle();
    expect(aiPanel, findsNothing);
    expect(find.text('信息'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('toggle-ai-panel')));
    await tester.pumpAndSettle();
    expect(aiPanel, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-ai-panel')));
    await tester.pumpAndSettle();
    expect(aiPanel, findsNothing);
  });

  testWidgets('Settings: an API key goes to the vault, not to ai.json', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    // Nothing listed until a provider is added.
    final add = find.byKey(const ValueKey('ai-add-provider'));
    await scrollTo(tester, add);
    expect(find.byKey(const ValueKey('ai-no-providers')), findsOneWidget);
    final tile = find.byKey(const ValueKey('ai-provider-tile-anthropic'));
    expect(tile, findsNothing);
    expect(find.text('OpenAI ChatGPT'), findsNothing);

    // Add -> pick the provider -> its editor.
    await tester.tap(add);
    await tester.pumpAndSettle();
    for (final v in ['anthropic', 'openai', 'deepseek', 'gemini', 'grok']) {
      expect(find.byKey(ValueKey('ai-add-$v')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('ai-add-custom')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-add-anthropic')));
    await tester.pumpAndSettle();

    // Saving without a key is refused.
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await tester.pumpAndSettle();
    expect(find.text('请输入 API Key'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('ai-key')), 'sk-ant-xyz');
    await tester.enterText(
      find.byKey(const ValueKey('ai-extra-models')),
      'my-model, other',
    );
    await tester.tap(find.byKey(const ValueKey('ai-save')));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(env.vault.read(AiConfigNotifier.keyName('anthropic')), 'sk-ant-xyz');
    final json = File('${env.dataDir.path}/ai.json').readAsStringSync();
    expect(json, contains('my-model'));
    expect(json, isNot(contains('sk-ant-xyz')));
    expect(
      find.descendant(of: tile, matching: find.textContaining('已配置')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai-no-providers')), findsNothing);

    // Already added: shown as such, can't be added twice.
    await tester.tap(add);
    await tester.pumpAndSettle();
    final item = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('ai-add-anthropic')),
    );
    expect(item.onPressed, isNull);
    expect(find.text('已添加'), findsOneWidget);
    expect(
      tester
          .widget<MenuItemButton>(find.byKey(const ValueKey('ai-add-openai')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('chat: pick a model, send, streamed reply with code block', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await configureAnthropic(tester, c);
    await openTab(tester, c);
    await tester.tap(find.byKey(const ValueKey('toggle-ai-panel')));
    await settleIo(tester);
    await tester.pumpAndSettle();

    // Model list comes from the provider; the first is picked.
    await pumpUntil(tester, () => tester.any(find.text('anthropic-model-a')));
    await tester.tap(find.byKey(const ValueKey('ai-model-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-provider-anthropic')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-model-anthropic-model-b')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('anthropic-model-b'), findsOneWidget);

    // Attach terminal output, then send with Enter.
    await tester.tap(find.byKey(const ValueKey('ai-attach-terminal')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '这是什么错误？');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpUntil(tester, () => tester.any(find.text('df -h')));
    await tester.pumpAndSettle();

    final req = env.ai.requests.single;
    expect(req.provider, 'anthropic');
    expect(req.model, 'anthropic-model-b');
    expect(req.system, contains('root@127.0.0.1:1'));
    final sent = req.turns.single.text;
    expect(sent, contains('<terminal>'));
    expect(sent, endsWith('这是什么错误？'));

    expect(find.text('这是什么错误？'), findsOneWidget);
    expect(find.text('已附带终端输出'), findsOneWidget);
    // Inline **bold** is rendered, not shown as asterisks.
    expect(find.textContaining('**'), findsNothing);
    expect(find.byKey(const ValueKey('ai-paste-to-terminal')), findsOneWidget);
    expect(
      c.read(aiConfigProvider).value!.selected?.model,
      'anthropic-model-b',
    );

    // A follow-up carries the history.
    await tester.enterText(find.byKey(const ValueKey('ai-input')), '继续');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    await pumpUntil(tester, () => env.ai.requests.length == 2);
    await tester.pumpAndSettle();
    final turns = env.ai.requests.last.turns;
    expect(turns.map((t) => t.fromUser), [true, false, true]);
    expect(turns[1].text, contains('df -h'));

    // New chat clears it.
    await tester.tap(find.byKey(const ValueKey('ai-new-chat')));
    await tester.pumpAndSettle();
    // A new chat: empty, no greeting or suggestions.
    expect(find.byKey(const ValueKey('ai-empty')), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    // The conversation was saved: open it again from the history.
    await settleIo(tester);
    await tester.tap(find.byKey(const ValueKey('ai-history')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-history-list')), findsOneWidget);
    expect(find.text('这台主机'), findsOneWidget);
    expect(find.text('这是什么错误？'), findsOneWidget);
    await tester.tap(find.text('这是什么错误？'));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-messages')), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    // Delete it from the list.
    await tester.tap(find.byKey(const ValueKey('ai-history')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    final id = c.read(aiHistoryProvider).value!.single.id;
    await tester.tap(find.byKey(ValueKey('ai-history-delete-$id')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('还没有历史对话'), findsOneWidget);
  });

  testWidgets('"allow all" is red, with a warning, and asks first', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const ValueKey('ai-tool-mode'));
    await scrollTo(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    final entry = find.text('全量允许（不再询问）');
    expect(entry, findsOneWidget);
    final red = Theme.of(tester.element(entry)).colorScheme.error;
    expect(tester.widget<Text>(entry).style?.color, red);
    final warn = find.descendant(
      of: find.ancestor(of: entry, matching: find.byType(MenuItemButton)),
      matching: find.byIcon(Icons.warning_amber_rounded),
    );
    expect(tester.widget<Icon>(warn).color, red);

    // Cancel keeps the old mode.
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('允许 AI 执行所有命令？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(c.read(aiConfigProvider).value!.toolMode, AiToolMode.autoReadOnly);

    // Confirm switches; the field shows it in red with the icon.
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全量允许（不再询问）').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-allow-all-confirm')));
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(c.read(aiConfigProvider).value!.toolMode, AiToolMode.allowAll);
    expect(
      find.descendant(
        of: dropdown,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
    final shown = find.descendant(
      of: dropdown,
      matching: find.text('全量允许（不再询问）'),
    );
    expect(tester.widget<Text>(shown).style?.color, red);
  });
}
