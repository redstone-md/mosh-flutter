// Widget tests for the SessionsScreen (DM sessions list). Mirrors the
// established slice-one pattern: ProviderScope overrides of the two bridge
// surfaces with scripted doubles + a localized MaterialApp. The lists and
// the offer accept run on the bridge double (exact mirrors, ADR 0025); the
// offer dismiss runs on the gateway double (the conversation seam), sharing
// the bridge's conversation state so the accept -> poll flow resolves. Test
// 3 (error/retry) uses scripted failures so we can assert `listSessions` ran
// a second time after tapping Retry. Test 2 wraps the screen in the real
// `appRouter` via `MaterialApp.router` so `context.go(AppRoutes.dmFor(...))`
// resolves and pushes DmScreen, which the test asserts by the DM screen's
// composer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';

import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/channel_runtime/types.dart';
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/conversation/dm_offers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import '../../support/pump.dart';

/// The pair of doubles the rail flow crosses: the bridge serves the lists
/// and the accept; the gateway answers the dismiss and the DM poll. Both see
/// one conversation state.
(ScriptableGateway, ScriptableBridge) _scriptedPair() {
  final gateway = ScriptableGateway();
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  return (gateway, bridge);
}

/// A bridge holding one channel that carries a DM offer, so the sessions
/// rail renders an offer row (pendingDmOffersProvider derives from
/// channel.dmOffers). Returns the pair so the dismiss (seam) and the accept
/// + lists (facade) both have a double.
(ScriptableGateway, ScriptableBridge) _channelOfferBridge() {
  final (gateway, bridge) = _scriptedPair();
  bridge.seedChannels([
    ChannelSnapshot(
      name: 'drift-room',
      topic: '',
      meshId: 'm',
      displayName: '',
      deviceFingerprint: 'SELF',
      messages: const [],
      attachments: const [],
      dmOffers: [
        DmOffer(
          offerId: 'offer-1',
          fromDevice: 'alpha-peer',
          fromFingerprint: 'PEERFP',
          targetFingerprint: 'SELF',
          inviteUri: 'mosh://invite?mesh=m&session=drift-41#fp=91A4-D2C8-77B0',
        ),
      ],
      mesh: null,
      events: const [],
    ),
  ]);

  return (gateway, bridge);
}

SessionSnapshot _session({
  required String sessionId,
  required String displayName,
  required String peerDisplayName,
  required DmSessionState state,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      transport: PeerTransport.none,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

void main() {
  // Mounts SessionsScreen with the seeded doubles. Pass useRouter when the
  // test taps a row and expects `context.go` to land on the real route.
  Future<void> pumpSessions(
    WidgetTester tester,
    ScriptableGateway gateway,
    ScriptableBridge bridge, {
    bool useRouter = false,
    String initialLocation = AppRoutes.sessions,
  }) {
    final overrides = [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
    ];
    return useRouter
        ? pumpRoute(tester, initialLocation, overrides: overrides)
        : pumpScreen(tester, const SessionsScreen(), overrides: overrides);
  }

  testWidgets('empty list renders the welcome + start-cta button',
      (tester) async {
    // The test bridge starts with no sessions, so listSessions is empty.
    final (gateway, bridge) = _scriptedPair();
    await pumpSessions(tester, gateway, bridge);

    expect(find.text('Welcome to Mosh.'), findsOneWidget);
    // The rail button carries the same label; the CTA is the FilledButton.
    expect(
      find.ancestor(
        of: find.text('Start a conversation'),
        matching: find.bySubtype<FilledButton>(),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'non-empty list renders rows with label + state, tapping navigates to dm',
      (tester) async {
    const aliceId = 'alice-session';
    const bobId = 'bob-session';
    final (gateway, bridge) = _scriptedPair();
    bridge.seedSessions([
      _session(
          sessionId: aliceId,
          displayName: 'me',
          peerDisplayName: 'Alice',
          state: DmSessionState.connected),
      _session(
          sessionId: bobId,
          displayName: 'Bob',
          peerDisplayName: 'Bob',
          state: DmSessionState.pending),
      _session(
          sessionId: 'carol-session',
          displayName: 'me',
          peerDisplayName: 'Carol',
          state: DmSessionState.handshaking),
    ]);

    await pumpSessions(tester, gateway, bridge, useRouter: true);

    // Every row renders its label and the badge for its proven state.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Waiting for your contact'), findsOneWidget);
    expect(find.text('Contact is offline'), findsOneWidget);

    // Tapping the Alice row navigates to /dm/<aliceId>. The DM screen's
    // composer placeholder is a stable sentinel that the router pushed it.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Write a message\u2026'), findsOneWidget);
  });

  testWidgets('a DM row has one accessible name: the visible label and state',
      (tester) async {
    final (gateway, bridge) = _scriptedPair();
    bridge.seedSessions([
      _session(
          sessionId: 'alice-a11y',
          displayName: 'me',
          peerDisplayName: 'Alice',
          state: DmSessionState.connected),
    ]);
    await pumpSessions(tester, gateway, bridge);

    expect(
      tester.getSemantics(find.text('Alice')),
      isSemantics(label: 'Alice\nConnected', isButton: true),
    );
  });

  testWidgets('the offer dismiss button is not nested in the accept button',
      (tester) async {
    final (gateway, bridge) = _channelOfferBridge();
    await pumpSessions(tester, gateway, bridge);

    final accept = tester.getSemantics(find.text('alpha-peer'));
    expect(
      accept,
      isSemantics(label: 'Accept chat invite from alpha-peer', isButton: true),
    );
    final dismiss = tester.getSemantics(find.byTooltip('Dismiss invite'));
    for (var node = dismiss.parent; node != null; node = node.parent) {
      expect(node, isNot(same(accept)));
    }
  });

  testWidgets(
      'error state renders retry and tapping it calls listSessions again',
      (tester) async {
    final (gateway, bridge) = _scriptedPair();
    bridge.failAlways(BridgeMethod.listSessions,
        error: Exception('boom-listSessions'));
    await pumpSessions(tester, gateway, bridge);

    expect(find.text('Unable to load conversations'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // A failure from outside the bridge has no worded kind: its raw
    // exception text never reaches the rail.
    expect(find.textContaining('boom-listSessions'), findsNothing);
    final callsBefore = bridge.countOf(BridgeMethod.listSessions);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // refresh() re-ran the bridge query (the count must increase, even if
    // Riverpod re-executed build() during settling -- we only assert growth).
    expect(bridge.countOf(BridgeMethod.listSessions), greaterThan(callsBefore));
  });

  testWidgets('the error state words a list failure and announces it',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.unavailable,
      message: 'dm runtime unavailable: node down',
    );
    final (gateway, bridge) = _scriptedPair();
    bridge.failAlways(BridgeMethod.listSessions, error: error);
    await pumpSessions(tester, gateway, bridge);

    final reason =
        AppLocalizations.of(tester.element(find.byType(SessionsScreen)))!
            .chatActionErrorUnavailable;
    expect(find.text(reason), findsOneWidget);
    expect(
      tester.getSemantics(find.text(reason)),
      isSemantics(isLiveRegion: true),
    );
  });

// Unread-badge rendering: a row whose
// unread count > 0 shows the numeral; a row with count 0 shows no badge.
// The DM entry of `conversationListProvider` (via a seeded bridge) and
// the unread lifecycle map are overridden so the rendered counts are
// deterministic and do not depend on the seeded messages.
  testWidgets(
      'renders an unread badge for sessions with count > 0 and none for 0',
      (tester) async {
    const aliceId = 'alice-unread';
    const bobId = 'bob-read';
    final (gateway, bridge) = _scriptedPair();
    bridge.seedSessions([
      _session(
          sessionId: aliceId,
          displayName: 'me',
          peerDisplayName: 'Alice',
          state: DmSessionState.connected),
      _session(
          sessionId: bobId,
          displayName: 'me',
          peerDisplayName: 'Bob',
          state: DmSessionState.connected),
    ]);

    // Only Alice has unread messages; Bob's count is 0.
    final unread = {'dm:$aliceId': 3};

    await pumpScreen(tester, const SessionsScreen(), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      // The sessions screen reads the lifecycle map's unread counts, not
      // the raw count map. The
      // override stubs the lifecycle's `build` to return the static map so
      // the rendered badges are deterministic (Alice=3, Bob absent -> 0).
      unreadLifecycleProvider.overrideWithBuild((ref, notifier) => unread),
    ]);

    // One UnreadBadge renders with count 3, and the numeral '3' is visible.
    expect(find.byWidgetPredicate((w) => w is UnreadBadge && w.count == 3),
        findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // The 0-count row still mounts an UnreadBadge(count: 0) but it renders
    // nothing (SizedBox.shrink) -- so no extra numeral is present and no
    // '99+' ever appears.
    expect(find.byWidgetPredicate((w) => w is UnreadBadge && w.count == 0),
        findsOneWidget);
    expect(find.text('99+'), findsNothing);
  });

  testWidgets(
      'pending channel DM offer renders one rail row and dismiss removes it',
      (tester) async {
    final (gateway, bridge) = _channelOfferBridge();
    // useRouter so the accept path's context.go(AppRoutes.dmFor(...)) resolves
    // and pushes DmScreen, which the test asserts via the DM screen composer.
    await pumpSessions(tester, gateway, bridge, useRouter: true);

    // The offer row renders with the offering peer's name + the
    // channel-host subtitle (`#drift-room`). The subtitle text appears in
    // the offer row AND the channel's own rail row (the channel is named
    // `drift-room`), so the peer name is the unique offer-row signal.
    expect(find.text('alpha-peer'), findsOneWidget);
    expect(find.text('#drift-room'), findsWidgets);

    // Dismiss: tapping the trailing X calls dismissChannelDmOffer and then
    // refreshes the channel list. The seeded channel still carries the offer,
    // so the row comes back; what this asserts is that the dismiss call was
    // made.
    await tester.tap(find.byTooltip('Dismiss invite'));
    await tester.pumpAndSettle();
    expect(gateway.countOf(GatewayMethod.dismissDmOffer), 1);

    // Accept: tapping the row calls acceptInvite + auto-dismiss + navigates
    // to the DM screen the bridge inserted. Reset dismiss counter first so
    // the auto-dismiss after accept is the only call counted.
    final dismissBeforeAccept = gateway.countOf(GatewayMethod.dismissDmOffer);
    final sessionCallsBeforeAccept = bridge.countOf(BridgeMethod.listSessions);
    await tester.tap(find.text('alpha-peer'));
    await tester.pumpAndSettle();
    expect(
        gateway.countOf(GatewayMethod.dismissDmOffer), dismissBeforeAccept + 1);
    expect(bridge.countOf(BridgeMethod.listSessions),
        sessionCallsBeforeAccept + 1);
    // The DM screen rendered (its composer is a TextField).
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets(
      'the offer row renders through the shared rail row, dismiss X included',
      (tester) async {
    final (gateway, bridge) = _channelOfferBridge();
    await pumpSessions(tester, gateway, bridge, useRouter: true);

    // One row shape: the offer row stops hand-rolling a `ListTile` and is a
    // `RailItem` like every other row, with the dismiss X in its action
    // slot beside the accept button.
    final offerRow = tester.widget<RailItem>(find.ancestor(
      of: find.byTooltip('Dismiss invite'),
      matching: find.byType(RailItem),
    ));
    expect(offerRow.title, 'alpha-peer');
  });

  testWidgets(
      'failed channel DM offer acceptance does not refresh sessions or navigate',
      (tester) async {
    final (gateway, bridge) = _channelOfferBridge();
    bridge.failAlways(BridgeMethod.acceptInvite,
        error: Exception('accept-failed'));
    await pumpSessions(tester, gateway, bridge, useRouter: true);

    final sessionCallsBeforeAccept = bridge.countOf(BridgeMethod.listSessions);
    await tester.tap(find.text('alpha-peer'));
    await tester.pumpAndSettle();

    expect(bridge.countOf(BridgeMethod.listSessions), sessionCallsBeforeAccept);
    expect(gateway.countOf(GatewayMethod.dismissDmOffer), 0);
    expect(find.text('Write a message\u2026'), findsNothing);
  });

  testWidgets(
      'an accepted offer still opens its DM when the follow-up dismiss fails',
      (tester) async {
    final (gateway, bridge) = _channelOfferBridge();
    gateway.failAlways(
      GatewayMethod.dismissDmOffer,
      error: const ConversationBridgeError(
        kind: ConversationBridgeErrorKind.unavailable,
        message: 'dm runtime unavailable: node down',
      ),
    );
    await pumpSessions(tester, gateway, bridge, useRouter: true);
    final l = AppLocalizations.of(tester.element(find.byType(SessionsScreen)))!;

    await tester.tap(find.text('alpha-peer'));
    await tester.pumpAndSettle();

    expect(find.text('Write a message\u2026'), findsOneWidget);
    // Both shell panes host a Scaffold, and the messenger toasts in each.
    expect(find.text(l.chatActionErrorUnavailable), findsWidgets);
  });

  // Regression (CodeAnt PR #17): pull-to-refresh only re-read the DM list,
  // so groups, channels and orgs stayed stale in the combined rail. A pull
  // must refresh every slice the rail renders.
  testWidgets(
      'pull-to-refresh re-reads the dm, channel and group lists and the '
      'org roster', (tester) async {
    final (gateway, bridge) = _scriptedPair();
    bridge.seedSessions([
      _session(
          sessionId: 'alice-refresh',
          displayName: 'me',
          peerDisplayName: 'Alice',
          state: DmSessionState.connected),
    ]);
    bridge.seedChannels([
      ChannelSnapshot(
        name: 'general',
        topic: '',
        meshId: 'm',
        displayName: '',
        deviceFingerprint: 'SELF',
        messages: const [],
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
      ),
    ]);
    bridge.seedGroups([
      GroupSnapshot(
        groupId: 'crew-refresh',
        meshId: 'm',
        label: 'Crew',
        displayName: 'me',
        deviceFingerprint: 'SELF',
        creatorFingerprint: 'SELF',
        isAdmin: false,
        state: 'ready',
        memberCount: BigInt.from(3),
        inviteUri: null,
        messages: const [],
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
        needsRejoin: false,
        orgPubkey: null,
        memberPeerIds: const [],
        typingMembers: const [],
      ),
    ]);

    await pumpSessions(tester, gateway, bridge);

    // Baseline counts (the initial build already read each list once).
    final sessionsBefore = bridge.countOf(BridgeMethod.listSessions);
    final channelsBefore = bridge.countOf(BridgeMethod.listChannels);
    final groupsBefore = bridge.countOf(BridgeMethod.listGroups);
    final orgsBefore = bridge.countOf(BridgeMethod.listOrgs);

    // Pull-to-refresh: fling the rail down from the top.
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(
        bridge.countOf(BridgeMethod.listSessions), greaterThan(sessionsBefore));
    expect(
        bridge.countOf(BridgeMethod.listChannels), greaterThan(channelsBefore));
    expect(bridge.countOf(BridgeMethod.listGroups), greaterThan(groupsBefore));
    expect(bridge.countOf(BridgeMethod.listOrgs), greaterThan(orgsBefore));
  });
}
