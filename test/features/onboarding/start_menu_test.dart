// The start menu in the chat pane at /chat: each card opens its step in
// place (the menu goes offstage, the step's header repeats the card
// title), and the step's Back returns to the menu. Steps are opened the
// way a person does, through `pumpStartStep`; the gateway and bridge are
// scripted because the real ones need the native library.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/group_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_join_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/start/start_step.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/start_menu.dart';

/// Every card title next to the step it opens.
const _cards = <(String, Type)>[
  ('Start a private chat', ChatCreateStep),
  ('Create a group', GroupCreateStep),
  ('Join with a link', OnboardJoinStep),
  ('Join a public channel', ChannelJoinStep),
];

void main() {
  for (final (title, step) in _cards) {
    testWidgets('"$title" opens its step inline', (tester) async {
      await pumpStartStep(tester, title, bridge: ScriptableBridge());

      expect(find.byType(step), findsOneWidget);
      expect(find.byType(StartMenu), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // The step's header repeats the card title.
      expect(
        find.descendant(of: find.byType(StartStep), matching: find.text(title)),
        findsOneWidget,
      );
    });

    testWidgets('Back from "$title" returns to the menu', (tester) async {
      await pumpStartStep(tester, title, bridge: ScriptableBridge());

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(StartMenu), findsOneWidget);
      expect(find.byType(step), findsNothing);
      // Every card is back on offer.
      for (final (card, _) in _cards) {
        expect(find.text(card), findsOneWidget);
      }
    });
  }
}
