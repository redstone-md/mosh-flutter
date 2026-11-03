// Creation/join workflows exercise the other cards through pumpStartStep.
// Link import keeps its own inline Back path, distinct from the /join route.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/start/start_step.dart';

import '../../support/scriptable_bridge.dart';
import '../../support/start_menu.dart';

void main() {
  testWidgets('"Join with a link" opens its step inline', (tester) async {
    await pumpStartStep(tester, 'Join with a link', bridge: ScriptableBridge());
    expect(find.byType(OnboardJoinStep), findsOneWidget);
    expect(find.byType(StartMenu), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
        find.descendant(
            of: find.byType(StartStep),
            matching: find.text('Join with a link')),
        findsOneWidget);
  });

  testWidgets('Back from "Join with a link" returns to the menu',
      (tester) async {
    await pumpStartStep(tester, 'Join with a link', bridge: ScriptableBridge());
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(OnboardJoinStep), findsNothing);
    for (final card in [
      'Start a private chat',
      'Create a group',
      'Join with a link',
      'Join a public channel',
    ]) {
      expect(find.text(card), findsOneWidget);
    }
  });
}
