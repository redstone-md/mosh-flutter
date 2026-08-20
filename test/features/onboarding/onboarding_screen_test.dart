// S4.4: widget test for the slice-one onboarding screen.
// Per ADR 0013 + S5 the gatewayProvider default is RealBridgeGateway (real
// Rust), which cannot run under `flutter test` (no native cdylib). The
// container must override gatewayProvider with the test gateway so any
// provider-backed read stays deterministic (the Chat tile no longer creates
// an invite inline -- it navigates to /chat-create -- but the override
// stays so the provider stays wired in this pump).
//
// S2-1+chat-create: tapping "New private chat" now navigates to the
// chat-create step (AppRoutes.chatCreate) instead of showing a SnackBar.
// The test pumps the screen through the real appRouter (MaterialApp.router)
// so context.go resolves and the ChatCreateScreen renders after the tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/features/onboarding/channel_join_screen.dart';
import 'package:mosh/src/features/onboarding/group_create_screen.dart';
import 'package:mosh/src/routing/app_router.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/pump.dart';

void main() {
  // Mounts the onboarding step with a test gateway. The routes come from
  // the app router, so a tile's `context.go` reaches the real screen.
  Future<ProviderContainer> pumpOnboarding(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      gatewayProvider.overrideWithValue(ScriptableGateway()),
    ]);
    addTearDown(container.dispose);
    await pumpRoute(tester, AppRoutes.onboarding, container: container);
    return container;
  }

  testWidgets(
      'onboarding renders title, binds name to inviteFlow, chat tile taps',
      (tester) async {
    final container = await pumpOnboarding(tester);

    // Title resolves from the ARB (en) -> "Start a conversation".
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);

    // Entering text must flow into inviteFlowProvider.displayName.
    await tester.enterText(find.byType(TextField), 'juno-laptop');
    await tester.pump();
    expect(container.read(inviteFlowProvider).displayName, 'juno-laptop');

    // Tapping the Chat tile navigates to /chat-create (the ChatCreateScreen
    // step), replacing the old SnackBar placeholder. No SnackBar renders.
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatCreateScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  // Channel tile (React OnboardMenu parity): the "Join" section now renders
  // the channel tile alongside the join tile, matching upstream's
  // NewSessionPanelMenu.tsx OnboardTile for onPick("channel"). The ChannelJoin
  // step + Gateway joinChannel seam is a later slice, so the tile reuses
  // _showLaterSlice (the same SnackBar the Group tile uses) -- this block
  // only asserts the tile renders.
  testWidgets('onboarding renders the channel tile in the Join section',
      (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Join a public channel'), findsOneWidget);
    expect(find.text('Open broadcast room, joined by name'), findsOneWidget);
  });

  // Channel tile (this atomic): tapping the channel tile now navigates to
  // the ChannelJoinScreen step (AppRoutes.channelJoin) instead of showing
  // the "later slice" SnackBar (mirrors the chat-tile navigation test above
  // for /chat-create). The ChannelJoin step's Join button is its own stub.
  testWidgets('channel tile navigates to the ChannelJoinScreen step',
      (tester) async {
    await pumpOnboarding(tester);

    // The channel tile title is unique to the Join section; tapping it
    // routes to /channel-join (ChannelJoinScreen), not a SnackBar.
    // The tile sits below the fold in the default 800x600 viewport, so
    // scroll it into view before tapping (matches how a user would scroll).
    await tester.scrollUntilVisible(
      find.text('Join a public channel'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Join a public channel'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelJoinScreen), findsOneWidget);
  });

  // Group tile (this atomic): tapping the group tile now navigates to the
  // GroupCreateScreen step (AppRoutes.groupCreate) instead of showing the
  // "later slice" SnackBar (mirrors the chat- and channel-tile navigation
  // tests). The GroupCreate step's Create button is its own stub.
  testWidgets('group tile navigates to the GroupCreateScreen step',
      (tester) async {
    await pumpOnboarding(tester);

    // The group tile title sits in the Start section; tapping it routes to
    // /group-create (GroupCreateScreen), not a SnackBar. The tile may sit
    // below the fold in the default 800x600 viewport, so scroll it into
    // view before tapping (matches how a user would scroll).
    await tester.scrollUntilVisible(
      find.text('New group'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupCreateScreen), findsOneWidget);
  });
}
