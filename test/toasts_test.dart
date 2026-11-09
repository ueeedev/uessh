import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/widgets/toasts.dart';

void main() {
  Future<void> pump(WidgetTester tester, {Widget? header}) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ToastLayer(header: header, child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  Finder card(String id) => find.byKey(ValueKey('toast-$id'));

  double opacityOf(WidgetTester tester, String id) => tester
      .widget<FadeTransition>(
        find
            .ancestor(of: card(id), matching: find.byType(FadeTransition))
            .first,
      )
      .opacity
      .value;

  testWidgets('top right, below the tab strip; slides and fades in', (
    tester,
  ) async {
    await pump(tester);
    showToast('已复制', id: 'a', kind: ToastKind.success);
    await tester.pump();
    expect(opacityOf(tester, 'a'), lessThan(0.2));
    await tester.pump(const Duration(milliseconds: 160));
    final mid = opacityOf(tester, 'a');
    expect(mid, greaterThan(0.2));
    expect(mid, lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'a'), 1);

    final rect = tester.getRect(card('a'));
    expect(rect.right, 1000 - 16);
    expect(rect.top, greaterThanOrEqualTo(ToastLayer.top));
    expect(find.text('已复制'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('leaves by itself, animating out', (tester) async {
    await pump(tester);
    showToast('x', id: 'a', duration: const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    // On its way out: still there, fading.
    expect(card('a'), findsOneWidget);
    expect(opacityOf(tester, 'a'), lessThan(1));
    await tester.pumpAndSettle();
    expect(card('a'), findsNothing);
    expect(toasts.entries, isEmpty);
  });

  testWidgets('stays while hovered; the close button closes it', (
    tester,
  ) async {
    await pump(tester);
    showToast('x', id: 'a', duration: const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(card('a')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(card('a'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toast-close-a')));
    await tester.pumpAndSettle();
    expect(card('a'), findsNothing);
  });

  testWidgets('same id replaces in place; newest below; at most 4', (
    tester,
  ) async {
    await pump(tester);
    showToast('下载中…', id: 'd', duration: null);
    showToast('其他', id: 'o');
    await tester.pumpAndSettle();
    final top = tester.getRect(card('d')).top;
    expect(tester.getRect(card('o')).top, greaterThan(top));

    showToast('已下载', id: 'd', kind: ToastKind.success);
    await tester.pumpAndSettle();
    expect(find.text('下载中…'), findsNothing);
    expect(find.text('已下载'), findsOneWidget);
    expect(tester.getRect(card('d')).top, top);

    for (var i = 0; i < 4; i++) {
      showToast('n$i', id: 'n$i');
    }
    await tester.pumpAndSettle();
    expect(card('d'), findsNothing); // the oldest left
    expect(card('o'), findsNothing);
    expect(card('n0'), findsOneWidget);
    expect(card('n3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('errors use the error colors', (tester) async {
    await pump(tester);
    showToast('失败', id: 'e', kind: ToastKind.error);
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(card('e'))).colorScheme;
    expect(tester.widget<Material>(card('e')).color, scheme.errorContainer);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the header (upload progress) sits above, animated', (
    tester,
  ) async {
    final show = ValueNotifier(false);
    await pump(
      tester,
      header: ValueListenableBuilder(
        valueListenable: show,
        builder: (_, on, _) => on
            ? const SizedBox(
                key: ValueKey('upload-progress'),
                width: 320,
                height: 60,
              )
            : const SizedBox.shrink(),
      ),
    );
    showToast('x', id: 'a');
    await tester.pumpAndSettle();
    show.value = true;
    await tester.pumpAndSettle();
    final upload = tester.getRect(
      find.byKey(const ValueKey('upload-progress')),
    );
    expect(upload.right, 1000 - 16);
    expect(upload.top, ToastLayer.top);
    expect(tester.getRect(card('a')).top, greaterThanOrEqualTo(upload.bottom));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
