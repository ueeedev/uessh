import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/app.dart';
import 'package:uessh/features/hosts/hosts_page.dart';
import 'package:uessh/widgets/side_sheet.dart';
import 'package:uessh/widgets/app_dropdown.dart';

import 'test_helpers.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: env.overrides, child: const UesshApp()),
    );
    await settleIo(tester);
  }

  testWidgets('starts on the hosts page', (tester) async {
    await pumpApp(tester);
    expect(find.text('还没有主机'), findsOneWidget);
  });

  testWidgets('switching to dark mode in settings updates the theme', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('add a host, then edit and delete it', (tester) async {
    await pumpApp(tester);

    // Create
    await tester.tap(find.text('新建主机'));
    await tester.pumpAndSettle();
    // Slides in from the right, full height, against the right edge.
    final sheet = tester.getRect(find.byType(SideSheet));
    expect(sheet.right, 1200);
    expect(sheet.left, greaterThan(600));
    expect(sheet.height, 800);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入地址'), findsOneWidget, reason: 'validation');

    await tester.enterText(find.widgetWithText(TextFormField, '名称'), '测试机');
    await tester.enterText(
      find.widgetWithText(TextFormField, '地址'),
      '10.0.0.5',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'root');
    await tester.enterText(find.widgetWithText(TextFormField, '密码'), 'hunter2');
    await tester.tap(find.text('保存'));
    await settleIo(tester);

    expect(find.text('测试机'), findsOneWidget);
    // The card shows only the name, not user / address.
    expect(find.textContaining('10.0.0.5'), findsNothing);
    final json = File('${env.dataDir.path}/hosts.json').readAsStringSync();
    expect(json, contains('10.0.0.5'));
    expect(json, isNot(contains('hunter2')));
    expect(env.secrets.values.values, contains('hunter2'));

    // Edit (the card's edit button opens the editor directly): the saved
    // password is pre-filled.
    expect(find.byTooltip('更多'), findsNothing, reason: 'no menu any more');
    await tester.tap(find.byTooltip('编辑'));
    await settleIo(tester);
    expect(find.text('编辑主机'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'hunter2'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '端口'), '2200');
    await tester.tap(find.text('保存'));
    await settleIo(tester);
    expect(
      File('${env.dataDir.path}/hosts.json').readAsStringSync(),
      contains('"port": 2200'),
    );

    // Delete from the bottom of the editor; asks first.
    await tester.tap(find.byTooltip('编辑'));
    await settleIo(tester);
    await tester.tap(find.byKey(const ValueKey('delete-host')));
    await tester.pumpAndSettle();
    expect(find.text('删除 测试机？'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑主机'), findsOneWidget, reason: 'cancel keeps it');

    await tester.tap(find.byKey(const ValueKey('delete-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settleIo(tester);
    expect(find.text('编辑主机'), findsNothing, reason: 'sheet closed');
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('还没有主机'), findsOneWidget);
    expect(env.secrets.values, isEmpty);
  });

  testWidgets('search bar and new-host button have the same height', (
    tester,
  ) async {
    await pumpApp(tester);
    final search = tester.getRect(find.byType(SearchBar));
    final button = tester.getRect(
      find.ancestor(
        of: find.text('新建主机'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(search.height, button.height);
    expect(search.center.dy, button.center.dy);
  });

  testWidgets('navigation labels sit to the right of their icons', (
    tester,
  ) async {
    await pumpApp(tester);
    final icon = tester.getRect(find.byIcon(Icons.settings_outlined));
    final label = tester.getRect(find.text('设置'));
    expect(label.left, greaterThan(icon.right));
    expect((label.center.dy - icon.center.dy).abs(), lessThan(2));
  });

  testWidgets('sidebar shows the logo left of the app name', (tester) async {
    await pumpApp(tester);
    final logo = tester.getRect(find.byKey(const ValueKey('app-logo')));
    final name = tester.getRect(find.text('uessh'));
    expect(logo.size, const Size(40, 40));
    expect(logo.right, lessThan(name.left));
    expect((logo.center.dy - name.center.dy).abs(), lessThan(2));
    expect(find.byIcon(Icons.terminal), findsNothing, reason: 'old icon gone');
  });

  testWidgets('each nav item is one button holding icon and label', (
    tester,
  ) async {
    await pumpApp(tester);
    final button = find.ancestor(
      of: find.text('设置'),
      matching: find.byType(InkWell),
    );
    expect(button, findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsOneWidget,
    );

    // Tapping the icon (not the text) also navigates, and the selected
    // highlight then covers the label too.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    // The page title is also "设置" now; the nav label comes first.
    final navLabel = find.text('设置').first;
    final pill = tester.getRect(
      find.ancestor(of: navLabel, matching: find.byType(Material)).first,
    );
    expect(pill.contains(tester.getCenter(navLabel)), isTrue);
    expect(
      pill.contains(tester.getCenter(find.byIcon(Icons.settings))),
      isTrue,
    );
    expect(find.text('外观'), findsOneWidget, reason: 'on settings page');
  });

  testWidgets('host editor closes with the close button', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('新建主机'));
    await tester.pumpAndSettle();
    expect(find.byType(SideSheet), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(SideSheet), findsNothing);
  });

  group('unsaved changes', () {
    Future<void> openNewHost(WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('新建主机'));
      await tester.pumpAndSettle();
    }

    Future<void> typeAddress(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, '地址'),
        '10.0.0.9',
      );
      await tester.pump(); // let the sheet rebuild with the new state
    }

    final confirm = find.text('放弃未保存的修改？');

    testWidgets('close button asks; "继续编辑" keeps the sheet and input', (
      tester,
    ) async {
      await openNewHost(tester);
      await typeAddress(tester);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);

      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.byType(SideSheet), findsOneWidget);
      expect(find.text('10.0.0.9'), findsOneWidget);
    });

    testWidgets('"放弃修改" closes the sheet without saving', (tester) async {
      await openNewHost(tester);
      await typeAddress(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);

      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.byType(SideSheet), findsNothing);
      expect(find.text('还没有主机'), findsOneWidget);
    });

    testWidgets('tapping the scrim asks too', (tester) async {
      await openNewHost(tester);
      await typeAddress(tester);
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);
    });

    testWidgets('Esc asks too', (tester) async {
      await openNewHost(tester);
      await typeAddress(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);
    });

    testWidgets('switching auth method counts as a change', (tester) async {
      await openNewHost(tester);
      await tester.tap(find.text('私钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);
    });

    testWidgets('no changes, or changes undone, close straight away', (
      tester,
    ) async {
      await openNewHost(tester);
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();
      expect(find.byType(SideSheet), findsNothing);

      await tester.tap(find.text('新建主机'));
      await tester.pumpAndSettle();
      await typeAddress(tester);
      await tester.enterText(find.widgetWithText(TextFormField, '地址'), '');
      await tester.pump();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.byType(SideSheet), findsNothing);
    });

    testWidgets('editing an existing host: untouched closes, change asks', (
      tester,
    ) async {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync(
        '{"version":1,"hosts":[{"id":"a","label":"web","address":"10.0.0.1",'
        '"port":22,"username":"root","authMethod":"password"}]}',
      );
      env.secrets.values['uessh.host.a.password'] = 'pw';
      await pumpApp(tester);

      Future<void> openEdit() async {
        await tester.tap(find.byTooltip('编辑'));
        await settleIo(tester);
      }

      // Loading the saved password must not count as a change.
      await openEdit();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.byType(SideSheet), findsNothing);

      await openEdit();
      await tester.enterText(find.widgetWithText(TextFormField, '端口'), '2022');
      await tester.pump();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(confirm, findsOneWidget);
    });

    testWidgets('saving closes without asking', (tester) async {
      await openNewHost(tester);
      await typeAddress(tester);
      await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'u');
      await tester.tap(find.text('保存'));
      await settleIo(tester);
      expect(confirm, findsNothing);
      expect(find.byType(SideSheet), findsNothing);
      expect(find.text('10.0.0.9'), findsOneWidget);
    });
  });

  group('host groups', () {
    void writeGroupedHosts() {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":2,
 "groups":[{"id":"g1","name":"生产"},{"id":"g2","name":"测试"}],
 "hosts":[
  {"id":"a","label":"web","address":"10.0.0.1","port":22,"username":"root","authMethod":"password","groupId":"g1"},
  {"id":"b","label":"db","address":"10.0.0.2","port":22,"username":"root","authMethod":"password","groupId":"g1"},
  {"id":"c","label":"loose","address":"10.0.0.3","port":22,"username":"root","authMethod":"password"}
 ]}''');
    }

    testWidgets('page shows a labeled divider per group, ungrouped last', (
      tester,
    ) async {
      writeGroupedHosts();
      await pumpApp(tester);

      final headers = find.byType(GroupHeader);
      expect(headers, findsNWidgets(3));
      final prod = tester.getRect(find.text('生产'));
      final test = tester.getRect(find.text('测试'));
      final none = tester.getRect(find.text('未分组'));
      expect(prod.top, lessThan(test.top));
      expect(test.top, lessThan(none.top));

      // The label sits left of its divider line.
      final line = tester.getRect(
        find.descendant(of: headers.first, matching: find.byType(Divider)),
      );
      expect(prod.right, lessThan(line.left));
      expect((prod.center.dy - line.center.dy).abs(), lessThan(4));

      // Hosts are under their own header; empty group shows a hint.
      expect(tester.getRect(find.text('web')).top, greaterThan(prod.bottom));
      expect(tester.getRect(find.text('web')).top, lessThan(test.top));
      expect(tester.getRect(find.text('loose')).top, greaterThan(none.bottom));
      expect(find.textContaining('这个分组还没有主机'), findsOneWidget);
    });

    testWidgets('divider lines hug their label and all end at the same x', (
      tester,
    ) async {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync(
        '''
{"version":2,
 "groups":[{"id":"g1","name":"A"},{"id":"g2","name":"一个名字特别特别特别长的分组用来测试截断用来测试截断"}],
 "hosts":[{"id":"c","label":"loose","address":"10.0.0.3","port":22,"username":"root","authMethod":"password"}]}''',
      );
      await pumpApp(tester);
      final headers = find.byType(GroupHeader);
      expect(headers, findsNWidgets(3)); // A, long name, ungrouped
      final ends = <double>{};
      for (var i = 0; i < 3; i++) {
        final header = headers.at(i);
        final line = tester.getRect(
          find.descendant(of: header, matching: find.byType(Divider)),
        );
        // The count text is the last thing before the line.
        final count = tester.getRect(
          find
              .descendant(of: header, matching: find.byType(Text))
              .evaluate()
              .map((e) => find.byWidget(e.widget))
              .firstWhere(
                (f) =>
                    RegExp(r'^\d+$')
                        .hasMatch((tester.widget<Text>(f)).data ?? ''),
              ),
        );
        expect(line.left - count.right, 12, reason: 'line hugs the label');
        expect(line.width, greaterThan(100), reason: 'long names are capped');
        ends.add(line.right);
      }
      expect(ends, hasLength(1), reason: 'all lines end at the same x');
    });

    testWidgets('no groups at all: no headers', (tester) async {
      File('${env.dataDir.path}/hosts.json').writeAsStringSync(
        '{"version":1,"hosts":[{"id":"a","label":"web","address":"x",'
        '"port":22,"username":"u","authMethod":"password"}]}',
      );
      await pumpApp(tester);
      expect(find.text('web'), findsOneWidget);
      expect(find.byType(GroupHeader), findsNothing);
    });

    testWidgets('searching a group name shows that group', (tester) async {
      writeGroupedHosts();
      await pumpApp(tester);
      await tester.enterText(find.byType(SearchBar), '生产');
      await tester.pumpAndSettle();
      expect(find.text('web'), findsOneWidget);
      expect(find.text('db'), findsOneWidget);
      expect(find.text('loose'), findsNothing);
      expect(find.text('测试'), findsNothing, reason: 'no matches there');
    });

    testWidgets('create a new group from the host editor', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('新建主机'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '地址'),
        '1.2.3.4',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'u');

      await tester.tap(find.text('新建分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('添加分组'));
      await tester.pumpAndSettle();
      expect(find.text('请输入分组名称'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '新分组名称'), '数据库');
      await tester.tap(find.byTooltip('添加分组'));
      await tester.pumpAndSettle();
      expect(find.text('数据库（新）'), findsWidgets, reason: 'selected, pending');

      await tester.tap(find.text('保存'));
      await settleIo(tester);
      expect(find.byType(SideSheet), findsNothing);
      expect(find.widgetWithText(GroupHeader, '数据库'), findsOneWidget);
      final json = File('${env.dataDir.path}/hosts.json').readAsStringSync();
      expect(json, contains('数据库'));
    });

    testWidgets('new group: buttons swap with animation, field width fixed', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('新建主机'));
      await tester.pumpAndSettle();
      final before = tester.getRect(
        find.byKey(const ValueKey('group-dropdown')),
      );
      final actions = tester.getRect(
        find.byKey(const ValueKey('group-actions')),
      );

      await tester.tap(find.text('新建分组'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-animation: both the old and the new controls are on screen.
      expect(find.byKey(const ValueKey('group-dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('new-group-field')), findsOneWidget);
      await tester.pumpAndSettle();

      final field = tester.getRect(
        find.byKey(const ValueKey('new-group-field')),
      );
      expect(field.left, before.left);
      expect(field.width, before.width, reason: 'left field keeps its size');
      expect(
        tester.getRect(find.byKey(const ValueKey('group-actions'))),
        actions,
      );
      expect(find.byTooltip('添加分组'), findsOneWidget);

      await tester.tap(find.byTooltip('取消新建'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('group-dropdown'))).width,
        before.width,
      );
    });

    testWidgets('pick an existing group; cancelling a new one keeps nothing', (
      tester,
    ) async {
      writeGroupedHosts();
      await pumpApp(tester);

      // Edit "loose" (ungrouped) and move it to 测试.
      await tester.tap(find.byTooltip('编辑').last);
      await settleIo(tester);
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await settleIo(tester);

      expect(find.text('未分组'), findsNothing, reason: 'no ungrouped left');
      final test = tester.getRect(find.widgetWithText(GroupHeader, '测试'));
      expect(tester.getRect(find.text('loose')).top, greaterThan(test.bottom));
      expect(find.textContaining('这个分组还没有主机'), findsNothing);
    });

    testWidgets('rename and delete a group from its header', (tester) async {
      writeGroupedHosts();
      await pumpApp(tester);

      await tester.tap(find.byTooltip('分组操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名分组'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '分组名称'), '测试');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('已经有同名的分组'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '分组名称'), '线上');
      await tester.tap(find.text('确定'));
      await settleIo(tester);
      expect(find.widgetWithText(GroupHeader, '线上'), findsOneWidget);
      expect(find.text('生产'), findsNothing);

      await tester.tap(find.byTooltip('分组操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除分组'));
      await tester.pumpAndSettle();
      expect(find.textContaining('组内 2 台主机会移到'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除分组'));
      await settleIo(tester);

      expect(find.text('线上'), findsNothing);
      expect(find.text('web'), findsOneWidget, reason: 'hosts are kept');
      final none = tester.getRect(find.widgetWithText(GroupHeader, '未分组'));
      expect(tester.getRect(find.text('web')).top, greaterThan(none.bottom));
    });
  });

  testWidgets('switching pages fades through and keeps page state', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(SearchBar), 'abc');
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Mid-transition: old page still fading out, new one not fully in.
    final opacities = [
      for (final e in find.byType(FadeTransition).evaluate())
        (e.widget as FadeTransition).opacity.value,
    ];
    expect(opacities.any((o) => o > 0 && o < 1), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('搜索主机'), findsNothing, reason: 'hosts page offstage');

    await tester.tap(find.text('主机').first);
    await tester.pumpAndSettle();
    expect(find.text('abc'), findsOneWidget, reason: 'search text kept');
  });

  testWidgets('dropdown menus open with an animation', (tester) async {
    final intervalArrow = find.descendant(
      of: find.byKey(const ValueKey('check-interval')),
      matching: find.byType(AnimatedRotation),
    );
    await pumpApp(tester);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(
      find.descendant(
        of: find.byKey(const ValueKey('check-interval')),
        matching: find.byType(MenuAnchor),
      ),
    );
    expect(anchor.animated, isTrue);

    await tester.tap(find.byKey(const ValueKey('check-interval')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final rot = tester.widget<AnimatedRotation>(intervalArrow);
    expect(rot.turns, 0.5, reason: 'arrow turns while open');
    await tester.pumpAndSettle();
    expect(find.text('5 分钟'), findsOneWidget);

    await tester.tap(find.text('5 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('5 分钟'), findsOneWidget, reason: 'now the value');
    expect(tester.widget<AnimatedRotation>(intervalArrow).turns, 0);
  });

  testWidgets('search filters the host list', (tester) async {
    File('${env.dataDir.path}/hosts.json').writeAsStringSync('''
{"version":1,"hosts":[
 {"id":"a","label":"web","address":"10.0.0.1","port":22,"username":"root","authMethod":"password"},
 {"id":"b","label":"db","address":"10.0.0.2","port":22,"username":"admin","authMethod":"key"}
]}''');
    await pumpApp(tester);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('db'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'admin');
    await tester.pumpAndSettle();
    expect(find.text('web'), findsNothing);
    expect(find.text('db'), findsOneWidget);
  });
}
