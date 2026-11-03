// IVO-50: the start menu answers the pointer quietly. A hovered or focused
// row lifts a step and its chevron edges forward; nothing leans or drifts.
// Reduced motion keeps the lift and drops the movement, here and in the
// join preview.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/onboarding/join_preview.dart';
import 'package:mosh/src/features/onboarding/start/start_hero.dart';
import 'package:mosh/src/features/onboarding/start/start_list.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import '../../support/pump.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool reduceMotion = false}) async {
  tester.view
    ..physicalSize = const Size(1200, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await pumpScreen(tester, Scaffold(body: Center(child: child)));
}

Widget _row({VoidCallback? onTap}) => SizedBox(
      width: 480,
      child: StartRow(
        action: StartAction(
          icon: Icons.link,
          accent: MoshColors.fg2,
          title: 'Join with a link',
          description: 'Join with an invite a contact sent you.',
          onTap: onTap ?? () {},
        ),
      ),
    );

Color? _surface(WidgetTester tester) => tester
    .widget<AnimatedContainer>(find.descendant(
        of: find.byType(StartRow), matching: find.byType(AnimatedContainer)))
    .decoration
    .let((d) => (d as BoxDecoration?)?.color);

Offset _chevronShift(WidgetTester tester) =>
    tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byType(StartRow)));
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  testWidgets('hovering lifts the row and edges the chevron; leaving drops it',
      (tester) async {
    await _pump(tester, _row());
    expect(_surface(tester), MoshColors.bg1);

    final mouse = await _hover(tester);
    expect(_surface(tester), MoshColors.bg2);
    expect(_chevronShift(tester).dx, greaterThan(0));

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(_surface(tester), MoshColors.bg1);
    expect(_chevronShift(tester), Offset.zero);
  });

  testWidgets('reduced motion lifts the row without moving the chevron',
      (tester) async {
    await _pump(tester, _row(), reduceMotion: true);
    await _hover(tester);
    expect(_surface(tester), MoshColors.bg2);
    expect(_chevronShift(tester), Offset.zero);
  });

  testWidgets('reduced motion swaps the join preview at once', (tester) async {
    await _pump(
        tester,
        const JoinPreview(
            kind: InviteDetectionKind.dm, title: 'Private chat invite'),
        reduceMotion: true);
    expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero);
  });

  testWidgets('Enter on a focused row opens it', (tester) async {
    var taps = 0;
    await _pump(tester, _row(onTap: () => taps++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_surface(tester), MoshColors.bg2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('the mark stays put under the pointer', (tester) async {
    await _pump(
        tester,
        const SizedBox(
            width: 480, child: StartHero(mark: true, titleSize: 40)));
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byType(Image));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(Image)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Image)), rest);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
