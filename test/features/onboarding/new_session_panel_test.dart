// The start menu and its steps share the chat pane. A step slides in
// beside the menu, keeps what was typed across a trip back, and swaps
// in place under reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/start/start_step.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

Future<void> _pumpWelcome(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1280, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpScreen(
    tester,
    const ChatPaneWelcome(),
    overrides: [gatewayProvider.overrideWithValue(ScriptableGateway())],
  );
}

Future<void> _open(WidgetTester tester, String card) async {
  await tester.ensureVisible(find.text(card));
  await tester.tap(find.text(card));
}

void main() {
  testWidgets('a step slides in over the menu and settles centred',
      (tester) async {
    await _pumpWelcome(tester);
    final pane = tester.getRect(find.byType(StartMenu));

    await _open(tester, 'Join a public channel');
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-slide both pages paint: the menu leaving, the step arriving.
    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(ChannelJoinStep), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(StartMenu), findsNothing);
    final step = tester.getRect(find.byType(ChannelJoinStep));
    expect(step.width, lessThanOrEqualTo(StartStep.maxWidth));
    expect(step.center.dx, moreOrLessEquals(pane.center.dx, epsilon: 1));
  });

  testWidgets('a step keeps its typed text across a trip to the menu',
      (tester) async {
    await _pumpWelcome(tester);
    await _open(tester, 'Join a public channel');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dev');

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await _open(tester, 'Join a public channel');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'dev'), findsOneWidget);
  });

  testWidgets('reduced motion swaps the step in place', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpWelcome(tester);

    await _open(tester, 'Join a public channel');
    await tester.pump();
    expect(find.byType(StartMenu), findsNothing);
    expect(find.byType(ChannelJoinStep), findsOneWidget);
  });
}
