// Ink ripples are motion. With the platform's reduce-motion setting on,
// every InkWell under MoshApp must stop animating a splash.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';

void main() {
  Future<InteractiveInkFeatureFactory> splashUnder(
      WidgetTester tester, bool disableAnimations) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: disableAnimations);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const ProviderScope(child: MoshApp()));
    await tester.pumpAndSettle();
    return Theme.of(tester.element(find.byType(SessionsScreen))).splashFactory;
  }

  testWidgets('reduce motion swaps the ripple for no splash', (tester) async {
    expect(await splashUnder(tester, true), NoSplash.splashFactory);
  });

  testWidgets('the default keeps the ripple', (tester) async {
    expect(await splashUnder(tester, false), isNot(NoSplash.splashFactory));
  });
}
