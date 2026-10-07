// IVO-50: the start menu answers the pointer. A hovered or focused card
// lights up and leans toward the pointer; the hero illustration stays
// still. Reduced motion keeps the light and drops the movement, here and
// in the join preview.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/onboarding/join_preview.dart';
import 'package:mosh/src/features/onboarding/start/start_card.dart';
import 'package:mosh/src/invite/invite_detection.dart';
import 'package:mosh/src/features/onboarding/start/start_hero.dart';
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

/// The arrow circle's fill: moss while the card is lit.
Color? _arrowFill(WidgetTester tester) {
  final circle = tester
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.shape == BoxShape.circle);
  return circle.color;
}

/// The card's lean: the first perspective transform under the card.
Matrix4 _lean(WidgetTester tester) => tester
    .widgetList<Transform>(find.descendant(
        of: find.byType(StartCard), matching: find.byType(Transform)))
    .first
    .transform;

// Cards take their row's height; alone, they take their own.
Widget _card({VoidCallback? onTap}) => SizedBox(
      width: 280,
      child: IntrinsicHeight(
          child: StartCard(
        icon: Icons.link,
        title: 'Join with a link',
        description: 'Join with an invite a contact sent you.',
        onTap: onTap ?? () {},
      )),
    );

void main() {
  testWidgets('hovering lights and leans the card; leaving settles it',
      (tester) async {
    await _pump(tester, _card());
    expect(_arrowFill(tester), MoshColors.bg3);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final card = tester.getRect(find.byType(StartCard));
    await mouse.moveTo(card.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_arrowFill(tester), MoshColors.moss);
    expect(_lean(tester), isNot(Matrix4.identity()..setEntry(3, 2, 0.001)));

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(_arrowFill(tester), MoshColors.bg3);
    expect(_lean(tester), Matrix4.identity()..setEntry(3, 2, 0.001));
  });

  testWidgets('reduced motion lights the card without leaning it',
      (tester) async {
    await _pump(tester, _card(), reduceMotion: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
        tester.getRect(find.byType(StartCard)).topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_arrowFill(tester), MoshColors.moss);
    expect(_lean(tester), Matrix4.identity()..setEntry(3, 2, 0.001));
    // The arrow fills but does not travel.
    expect(tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
        Offset.zero);
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

  testWidgets('Enter on a focused card opens it', (tester) async {
    var taps = 0;
    await _pump(tester, _card(onTap: () => taps++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_arrowFill(tester), MoshColors.moss);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('the illustration stays put under the pointer', (tester) async {
    await _pump(tester,
        const SizedBox(width: 1100, child: StartHero(illustrated: true)));
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byType(Image));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
        tester.getTopRight(find.byType(StartHero)) + const Offset(-5, 5));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Image)), rest);
  });
}
