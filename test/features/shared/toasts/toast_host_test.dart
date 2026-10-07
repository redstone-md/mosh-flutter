// IVO-30: toasts render once over the app, in Mosh's theme, announce
// themselves, close on a timer, a button or a swipe, and never block the
// screen around them.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toast_card.dart';
import 'package:mosh/src/features/shared/toasts/toast_host.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';

Future<Toaster> _pump(WidgetTester tester,
    {Size size = const Size(1280, 800), VoidCallback? onTapBehind}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => ToastHost(child: child!),
      home: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapBehind,
          child: const SizedBox.expand(),
        ),
      ),
    ),
  ));
  // The app's own toaster, disposed with the scope like in the app.
  return ProviderScope.containerOf(tester.element(find.byType(ToastHost)))
      .read(toasterProvider);
}

void main() {
  testWidgets('a toast shows once and closes on its timer', (tester) async {
    final toaster = await _pump(tester);
    toaster.show('Copied', kind: ToastKind.success);
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('screen readers hear each toast, errors interrupt',
      (tester) async {
    final toaster = await _pump(tester);
    toaster
      ..show('Copied', kind: ToastKind.success)
      ..show('Failed', kind: ToastKind.error);
    await tester.pumpAndSettle();
    toaster.show('Copied', kind: ToastKind.success);
    await tester.pumpAndSettle();
    final heard = tester.takeAnnouncements();
    expect([for (final a in heard) a.message], ['Copied', 'Failed', 'Copied']);
    expect(heard[1].assertiveness, Assertiveness.assertive);
    expect(heard[0].assertiveness, Assertiveness.polite);
  });

  testWidgets('the close button dismisses and is named', (tester) async {
    final semantics = tester.ensureSemantics();
    final toaster = await _pump(tester);
    toaster.show('Copied');
    await tester.pumpAndSettle();
    final close = find.bySemanticsLabel('Dismiss notification');
    expect(close, findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a swipe toward the edge dismisses, a short one springs back',
      (tester) async {
    final toaster = await _pump(tester);
    toaster.show('Copied');
    await tester.pumpAndSettle();
    final rest = tester.getTopLeft(find.byType(ToastCard));
    await tester.timedDrag(
        find.text('Copied'), const Offset(0, -12), const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(ToastCard)), rest);
    await tester.drag(find.text('Copied'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('hovering fans the stack out and holds its timers',
      (tester) async {
    final toaster = await _pump(tester);
    toaster
      ..show('one')
      ..show('two');
    await tester.pumpAndSettle();
    final cards = find.byType(ToastCard);
    // Folded: the older toast hides behind the newer one.
    expect(tester.getTopLeft(cards.at(0)).dy,
        moreOrLessEquals(tester.getTopLeft(cards.at(1)).dy, epsilon: 13));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('two')));
    await tester.pumpAndSettle();
    // Fanned: the older one sits fully below the newer one.
    expect(tester.getTopLeft(find.text('one')).dy,
        greaterThan(tester.getBottomLeft(find.text('two')).dy));
    await tester.pump(const Duration(seconds: 10));
    expect(toaster.toasts, hasLength(2));
    await mouse.moveTo(const Offset(5, 790));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(toaster.toasts, isEmpty);
    await mouse.removePointer();
  });

  testWidgets('taps around the stack reach the screen below', (tester) async {
    var taps = 0;
    final toaster = await _pump(tester, onTapBehind: () => taps++);
    toaster.show('Copied');
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(ToastCard));
    await tester.tapAt(card.centerLeft - const Offset(20, 0));
    await tester.tapAt(card.bottomCenter + const Offset(0, 40));
    expect(taps, 2);
  });

  testWidgets('phones show toasts above the composer', (tester) async {
    final toaster = await _pump(tester, size: const Size(390, 844));
    toaster.show('Copied');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ToastCard)).bottom,
        moreOrLessEquals(844 - 88, epsilon: 1));
  });

  testWidgets('reduced motion swaps toasts in place', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final toaster = await _pump(tester);
    toaster.show('Copied');
    await tester.pump();
    await tester.pump();
    expect(tester.widget<ToastCard>(find.byType(ToastCard)).pose.opacity, 1);
    expect(tester.widget<ToastCard>(find.byType(ToastCard)).pose.dy, 0);
  });

  testWidgets('closing the app leaves no toast timer behind', (tester) async {
    final toaster = await _pump(tester);
    toaster
      ..show('one')
      ..show('two', kind: ToastKind.error);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a replaced scope shows its own toasts', (tester) async {
    Future<Toaster> mount() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ToastHost(child: child!),
          home: const SizedBox(),
        ),
      ));
      return container.read(toasterProvider);
    }

    final first = await mount();
    first.show('old');
    await tester.pumpAndSettle();
    final second = await mount();
    // The old scope's stack went with the host that showed it.
    expect(first.toasts, isEmpty);
    second.show('new');
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });
}
