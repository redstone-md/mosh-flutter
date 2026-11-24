// IVO-50: the start menu answers the pointer quietly: a row takes the state
// layer of any control and nothing leans or drifts. Reduced motion drops the
// movement of the join preview.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_icons.dart';
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
          icon: MoshIcons.link,
          accent: MoshColors.dark.onSurfaceVariant,
          title: 'Join with a link',
          description: 'Join with an invite a contact sent you.',
          onTap: onTap ?? () {},
        ),
      ),
    );

void main() {
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
