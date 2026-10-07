// Widget tests for the channel-join step (ChannelJoinStep), opened the way
// a person does: the start menu in the chat pane at /chat, then a tap on
// the "Join a public channel" card (`pumpStartStep`). The bridge is
// scripted.
//
// Test 1: initial state -- lead, unencrypted warning, field, button, the
//   example names.
// Test 2: Join is disabled while the name is empty; enabled on text.
// Test 3: an example chip fills the field and enables Join.
// Test 4: tapping Join calls the bridge's joinChannel and navigates to the
//   channel screen.
// Test 5: the route follows the name the core normalized (IVO-50).
// Test 6: Back returns to the start menu.
// Tests 7-8: a failed join shows a persistent inline error, worded by the
//   bridge error's kind, never a SnackBar, and stays on the step.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/channel_screen.dart';
import 'package:mosh/src/features/onboarding/channel_join_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/gateway_snapshots.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import '../../support/start_menu.dart';

const _card = 'Join a public channel';
const _warning =
    'End-to-end encryption is disabled for public channels. Anyone who joins this channel can read messages.';

Finder _inStep(Finder matching) =>
    find.descendant(of: find.byType(ChannelJoinStep), matching: matching);

final _nameField = _inStep(find.byType(TextField));
final _joinButton = _inStep(find.byType(FilledButton));

void main() {
  Future<void> pumpJoinStep(WidgetTester tester, {ScriptableBridge? bridge}) =>
      pumpStartStep(tester, _card, bridge: bridge ?? ScriptableBridge());

  FilledButton joinButton(WidgetTester tester) =>
      tester.widget<FilledButton>(_joinButton);

  Future<void> join(WidgetTester tester, String name) async {
    await tester.enterText(_nameField, name);
    await tester.pump();
    await tester.tap(_joinButton);
    await tester.pumpAndSettle();
  }

  testWidgets('initial state renders lead, warning, field, button, examples',
      (tester) async {
    await pumpJoinStep(tester);

    expect(find.text('Join an open room by its name.'), findsOneWidget);
    expect(find.text(_warning), findsOneWidget);
    expect(find.text('Channel name'), findsOneWidget);
    expect(find.text('Join channel'), findsOneWidget);
    for (final name in ['news', 'dev', 'community']) {
      expect(find.widgetWithText(ActionChip, name), findsOneWidget);
    }
  });

  testWidgets(
      'Join button is disabled when name is empty and enabled after text entry',
      (tester) async {
    await pumpJoinStep(tester);

    expect(joinButton(tester).onPressed, isNull);

    await tester.enterText(_nameField, 'test-channel');
    await tester.pump();
    expect(joinButton(tester).onPressed, isNotNull);
  });

  testWidgets('tapping an example fills the field and enables Join',
      (tester) async {
    await pumpJoinStep(tester);

    final chip = find.widgetWithText(ActionChip, 'dev');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();

    expect(tester.widget<TextField>(_nameField).controller!.text, 'dev');
    expect(joinButton(tester).onPressed, isNotNull);
  });

  testWidgets(
      'tapping Join with a name entered joins via the bridge and navigates to the channel screen',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpJoinStep(tester, bridge: bridge);

    await join(tester, 'test-channel');

    expect(find.byType(ChannelScreen), findsOneWidget);
    expect(find.byType(ChannelJoinStep), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Reading the notifier initializes the provider once, then the explicit
    // post-join refresh performs the second fetch.
    expect(bridge.countOf(BridgeMethod.listChannels), 2);
  });

  // IVO-50: the core lowercases and strips `#`; the route must follow the
  // name the core joined, not the raw input.
  testWidgets('joining opens the channel by the name the core normalized',
      (tester) async {
    final bridge = ScriptableBridge();
    bridge.conversations.channels['#News'] =
        cannedChannelSnapshot(name: 'news', displayName: '');
    final container = ProviderContainer(overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(ScriptableGateway()),
    ]);
    addTearDown(container.dispose);
    final router = await pumpStartStep(tester, _card, container: container);

    await join(tester, '#News');

    expect(router.routeInformationProvider.value.uri.path,
        AppRoutes.channelFor('news'));
  });

  testWidgets('Back returns to the start menu', (tester) async {
    await pumpJoinStep(tester);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(StartMenu), findsOneWidget);
    expect(find.byType(ChannelJoinStep), findsNothing);
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

    await join(tester, 'test-channel');

    final l =
        AppLocalizations.of(tester.element(find.byType(ChannelJoinStep)))!;
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

    await join(tester, 'test-channel');

    // A non-bridge error renders as its own text (the classifier's text
    // arm) and the inline error is the ONE source of feedback -- no
    // transient SnackBar, and we did NOT navigate to the channel screen.
    expect(find.text(message), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ChannelScreen), findsNothing);
    expect(find.byType(ChannelJoinStep), findsOneWidget);
    // A failed join must not initialize or refresh the channel list.
    expect(throwing.countOf(BridgeMethod.listChannels), 0);
  });
}
