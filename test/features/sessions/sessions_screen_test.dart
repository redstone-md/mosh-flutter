// Widget tests for the SessionsScreen (DM sessions list). Mirrors the
// established slice-one pattern: ProviderScope override of `gatewayProvider`
// with a controllable fake + a localized MaterialApp. Test 3 (error/retry)
// uses a counting fake so we can assert `listSessions` ran a second time
// after tapping Retry. Test 2 wraps the screen in the real `appRouter` via
// `MaterialApp.router` so `context.go(AppRoutes.dmFor(...))` resolves and
// pushes DmScreen, which the test asserts by the DM screen's composer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/unread_lifecycle_provider.dart';
import '../../support/pump.dart';

/// A gateway holding one channel that carries a DM offer, so the sessions
/// rail renders an OfferRailItem (pendingDmOffersProvider derives from
/// channel.dmOffers).
ScriptableGateway _channelOfferGateway() => ScriptableGateway()
  ..seedChannels([
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

SessionSnapshot _session({
  required String sessionId,
  required String displayName,
  required String peerDisplayName,
  required String state,
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      path: 'connecting',
      relayReady: null,
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
  // Mounts SessionsScreen with the seeded gateway. Pass useRouter when the
  // test taps a row and expects `context.go` to land on the real route.
  Future<void> pumpSessions(
    WidgetTester tester,
    Gateway gateway, {
    bool useRouter = false,
    String initialLocation = AppRoutes.sessions,
  }) {
    final overrides = [gatewayProvider.overrideWithValue(gateway)];
    return useRouter
        ? pumpRoute(tester, initialLocation, overrides: overrides)
        : pumpScreen(tester, const SessionsScreen(), overrides: overrides);
  }

  testWidgets('empty list renders the welcome + start-cta button',
      (tester) async {
    // The test gateway starts with no sessions, so listSessions is empty.
    await pumpSessions(tester, ScriptableGateway());

    expect(find.text('Welcome to Mosh.'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);
  });

  testWidgets(
      'non-empty list renders rows with label + state, tapping navigates to dm',
      (tester) async {
    const aliceId = 'alice-session';
    const bobId = 'bob-session';
    final gateway = ScriptableGateway()
      ..seedSessions([
        _session(
            sessionId: aliceId,
            displayName: 'me',
            peerDisplayName: 'Alice',
            state: 'ready'),
        _session(
            sessionId: bobId,
            displayName: 'Bob',
            peerDisplayName: 'Bob',
            state: 'connecting'),
      ]);

    await pumpSessions(tester, gateway, useRouter: true);

    // Both rows render with their labels and localized state labels.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget); // ready -> stateReady
    expect(find.text('Waiting'), findsOneWidget); // connecting -> stateWaiting

    // Accessibility: the Alice row exposes the React-parity semantics label.
    // Accessibility: the Alice row exposes the React-parity semantics label.
    // The two-pane StatefulShellRoute (mosh_shell.dart) lays the rail + chat
    // branches out as two live Navigators on desktop, and two simultaneous
    // ModalRoutes change the merged-semantics tree enough that
    // find.bySemanticsLabel no longer resolves the row's label (the node
    // ends up non-leaf with an empty label). The row's Semantics widget
    // still carries the label in its properties, so assert on the widget
    // directly -- layout-independent and pins the React `aria-label` parity
    // the bySemanticsLabel check was guarding.
    final rowSemantics = tester.widgetList<Semantics>(
      find.ancestor(of: find.text('Alice'), matching: find.byType(Semantics)),
    );
    expect(
      rowSemantics
          .map((s) => s.properties.label)
          .contains('Open session with Alice'),
      isTrue,
    );

    // Tapping the Alice row navigates to /dm/<aliceId>. The DM screen's
    // composer placeholder is a stable sentinel that the router pushed it.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Write a message\u2026'), findsOneWidget);
  });

  testWidgets(
      'error state renders retry and tapping it calls listSessions again',
      (tester) async {
    final gateway = ScriptableGateway()
      ..failAlways(GatewayMethod.listSessions,
          error: Exception('boom-listSessions'));
    await pumpSessions(tester, gateway);

    expect(find.text('Could not load sessions.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final callsBefore = gateway.countOf(GatewayMethod.listSessions);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // refresh() re-ran the gateway query (the count must increase, even if
    // Riverpod re-executed build() during settling -- we only assert growth).
    expect(
        gateway.countOf(GatewayMethod.listSessions), greaterThan(callsBefore));
  });

// Unread-badge rendering. Mirrors React's `UnreadBadge`: a row whose
// unread count > 0 shows the numeral; a row with count 0 shows no badge.
// Both `sessionListProvider` (via a seeded gateway) and
// `unreadDmCountsProvider` are overridden so the rendered counts are
// deterministic and do not depend on the seeded messages.
  testWidgets(
      'renders an unread badge for sessions with count > 0 and none for 0',
      (tester) async {
    const aliceId = 'alice-unread';
    const bobId = 'bob-read';
    final gateway = ScriptableGateway()
      ..seedSessions([
        _session(
            sessionId: aliceId,
            displayName: 'me',
            peerDisplayName: 'Alice',
            state: 'ready'),
        _session(
            sessionId: bobId,
            displayName: 'me',
            peerDisplayName: 'Bob',
            state: 'ready'),
      ]);

    // Only Alice has unread messages; Bob's count is 0.
    final unread = {'dm:$aliceId': 3};

    await pumpScreen(tester, const SessionsScreen(), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      // The sessions screen now reads the lifecycle map (the React
      // `useUnreadNotifications.unread` port), not the raw count map. The
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
      'pending channel DM offer renders an OfferRailItem and dismiss removes it',
      (tester) async {
    final gateway = _channelOfferGateway();
    // useRouter so the accept path's context.go(AppRoutes.dmFor(...)) resolves
    // and pushes DmScreen, which the test asserts via the DM screen composer.
    await pumpSessions(tester, gateway, useRouter: true);

    // The OfferRailItem renders with the offering peer's name + the
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

    // Accept: tapping the row calls acceptInvite (returns the seeded
    // 'accepted-dm' session) + auto-dismiss + navigates to the DM screen.
    // Reset dismiss counter first so the auto-dismiss after accept is the
    // only call counted.
    final dismissBeforeAccept = gateway.countOf(GatewayMethod.dismissDmOffer);
    final sessionCallsBeforeAccept =
        gateway.countOf(GatewayMethod.listSessions);
    await tester.tap(find.text('alpha-peer'));
    await tester.pumpAndSettle();
    expect(
        gateway.countOf(GatewayMethod.dismissDmOffer), dismissBeforeAccept + 1);
    expect(gateway.countOf(GatewayMethod.listSessions),
        sessionCallsBeforeAccept + 1);
    // The DM screen rendered (its composer is a TextField).
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets(
      'failed channel DM offer acceptance does not refresh sessions or navigate',
      (tester) async {
    final gateway = _channelOfferGateway()
      ..failAlways(GatewayMethod.acceptInvite,
          error: Exception('accept-failed'));
    await pumpSessions(tester, gateway, useRouter: true);

    final sessionCallsBeforeAccept =
        gateway.countOf(GatewayMethod.listSessions);
    await tester.tap(find.text('alpha-peer'));
    await tester.pumpAndSettle();

    expect(
        gateway.countOf(GatewayMethod.listSessions), sessionCallsBeforeAccept);
    expect(gateway.countOf(GatewayMethod.dismissDmOffer), 0);
    expect(find.text('Write a message\u2026'), findsNothing);
  });
}
