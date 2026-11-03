import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/shared/press_scale.dart';

import '../../support/pump.dart';

Future<void> _testPressScaleInteraction(WidgetTester tester) async {
  var tapped = false;
  await pumpScreen(
    tester,
    PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => tapped = true,
        child: const SizedBox(width: 100, height: 100),
      ),
    ),
  );

  final finder = find.byType(AnimatedScale);
  expect(finder, findsOneWidget);
  expect(tester.widget<AnimatedScale>(finder).scale, 1.0);

  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump();
  expect(tester.widget<AnimatedScale>(finder).scale, 0.96);

  await gesture.up();
  await tester.pumpAndSettle();
  expect(tester.widget<AnimatedScale>(finder).scale, 1.0);
  expect(tapped, isTrue);
}

void main() {
  testWidgets('PressScale scales down on pointer down and restores on up',
      _testPressScaleInteraction);

  testWidgets('PressScale is a no-op when enabled is false', (tester) async {
    await pumpScreen(
      tester,
      const PressScale(
        enabled: false,
        child: SizedBox(width: 100, height: 100),
      ),
    );
    expect(find.byType(AnimatedScale), findsNothing);
    expect(find.byType(SizedBox), findsOneWidget);
  });
}
