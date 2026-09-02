// Widget tests for the ChannelJoinScreen (channel-join step, 1-в-1 with the
// React ChannelJoinStep). Mirrors the chat_create_screen_test boilerplate:
// ProviderScope override of `bridgeFacadeProvider` with the scripted bridge +
// localized
// MaterialApp.router so the step's Back button (context.go) resolves.
//
// Test 1: initial state -- title + body + placeholder + `#` + button label.
// Test 2: Join button is disabled when the name is empty; enabling on text.
// Test 3: tapping Join (with a name entered) calls the bridge's joinChannel
//   (canned snapshot) and navigates to the channel screen (slice-3 seam).
// Test 4: Back button returns to the onboarding menu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/onboarding/channel_join_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import '../../support/scriptable_bridge.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import '../../support/pump.dart';

void main() {
  Future<void> pumpJoinStep(
    WidgetTester tester, {
    BridgeFacade? bridge,
    String initialLocation = AppRoutes.channelJoin,
  }) {
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge ?? ScriptableBridge()),
    ]);
    addTearDown(container.dispose);
    return pumpRoute(tester, initialLocation, container: container);
  }

  testWidgets(
      'initial state renders title, body, placeholder, `#` prefix, and button label',
      (tester) async {
    await pumpJoinStep(tester);

    expect(find.text('Join a public channel'), findsOneWidget);
    expect(
      find.text(
        'Public channels are not end-to-end encrypted \u2014 anyone who knows the name can read along.',
      ),
      findsOneWidget,
    );
    expect(find.text('channel-name'), findsOneWidget);
    expect(find.text('Join channel'), findsOneWidget);
    expect(find.text('#'), findsOneWidget);
  });

  testWidgets(
      'Join button is disabled when name is empty and enabled after text entry',
      (tester) async {
    await pumpJoinStep(tester);

    // Empty name -> disabled (onPressed is null).
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    // Enter text -> enabled (onPressed is not null).
    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    final enabledButton =
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets(
      'tapping Join with a name entered joins via the bridge and navigates to the channel screen',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpJoinStep(tester, bridge: bridge);

    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The joinChannel seam (slice-3) calls the bridge's joinChannel (returns
    // a canned ChannelSnapshot for 'test-channel') and navigates to the
    // channel screen. No SnackBar on the happy path.
    expect(find.byType(ChannelScreen), findsOneWidget);
    expect(find.byType(ChannelJoinScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Reading the notifier initializes the provider once, then the explicit
    // post-join refresh performs the second fetch.
    expect(bridge.countOf(BridgeMethod.listChannels), 2);
  });

  testWidgets('Back button returns to the onboarding menu', (tester) async {
    await pumpJoinStep(tester);

    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears and
    // the step screen is gone.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(ChannelJoinScreen), findsNothing);
  });

  // The bridge throws the generated ConversationBridgeError (ticket 17); the
  // step words the inline error by its kind and never shows the runtime's
  // diagnostic sentence (ticket 18).
  testWidgets('a failed join is worded by the bridge error\'s kind',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.unavailable,
      message: 'channel runtime unavailable: node down',
    );
    final throwing = ScriptableBridge()
      ..failAlways(BridgeMethod.joinChannel, error: error);
    await pumpJoinStep(tester, bridge: throwing);

    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final l =
        AppLocalizations.of(tester.element(find.byType(ChannelJoinScreen)))!;
    expect(find.text(l.chatActionErrorUnavailable), findsOneWidget);
    expect(find.textContaining(error.message), findsNothing);
    expect(find.textContaining('Instance of'), findsNothing);
  });

  testWidgets(
      'a failed join surfaces a persistent inline error (role="alert") and no SnackBar',
      (tester) async {
    const message = 'Channel runtime offline';
    final throwing = ScriptableBridge()
      ..failAlways(BridgeMethod.joinChannel, error: message);
    await pumpJoinStep(tester, bridge: throwing);

    await tester.enterText(find.byType(TextField), 'test-channel');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // The inline error renders the raw error string verbatim (React
    // `{props.error}` stringifies the caught error) and is the ONE source
    // of feedback -- no transient SnackBar (the old SnackBar path is gone),
    // and we did NOT navigate to the channel screen.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ChannelScreen), findsNothing);
    expect(find.byType(ChannelJoinScreen), findsOneWidget);
    // A failed join must not initialize or refresh the channel list.
    expect(throwing.countOf(BridgeMethod.listChannels), 0);
  });
}
