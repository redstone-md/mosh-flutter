// Shell tests pinning the two-pane StatefulShellRoute -- the React
// private-dm-screen desktop-body parity gap (private-dm-screen.tsx:243-343
// + use-conversation-rail-state.ts:1-38). The shell (mosh_shell.dart) lays
// out the rail branch (A) + chat branch (B) side-by-side on desktop (rail
// ALWAYS visible beside the chat) and as a single pane on mobile (rail OR
// chat). These tests pin both layouts so a regression that re-flattens
// the routes (rail disappears while reading a DM) fails loudly.
//
// The tests pump the real MoshApp (which owns the process-global appRouter)
// inside a ProviderScope overriding gatewayProvider with a FakeGateway
// subclass whose listSessions + pollSession return one seeded DM session
// (peer display name 'Alice' / 'Bob'). The surface width is set via
// tester.view.physicalSize + devicePixelRatio so isMobileBreakpoint
// (MediaQuery.sizeOf, width <= 580) reads the test width.
//
// Cases:
//   1. Desktop (1200x900): /sessions shows the rail (SessionsScreen) AND
//      the welcome pane (ChatPaneWelcome) side-by-side. Tapping the DM row
//      swaps the chat pane to DmScreen while the rail STAYS visible.
//   2. Mobile (400x800): /sessions shows the rail ALONE (no welcome pane).
//      Tapping the DM row swaps to DmScreen and the rail is GONE. Leaving
//      the DM (close + confirm) returns to the rail.
//   3. Desktop (1200x900): tapping the shared titlebar's "Peer status"
//      button mounts the shell-level PeerStatusDrawer (Positioned.fill
//      over rail + chat); tapping the drawer's close button unmounts it.
//      Regression guard for the titlebar-owned-_showPeerStatus bug (the
//      shell never rebuilt when the titlebar flipped its private toggle,
//      so the tap silently no-opped).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/main.dart';
import 'package:mosh/src/features/dm/peer_status_drawer.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

// Seeded FakeGateway: listSessions + pollSession return one DM session
// with the given peer display name, so the rail renders one row AND the DM
// screen resolves without the native cdylib. closeSession removes the
// seeded session so the leave-flow's context.go('/sessions') returns to an
// empty rail (mirrors the real close).
class _SeededGateway extends FakeGateway {
  _SeededGateway(this._snapshot);

  final SessionSnapshot _snapshot;
  bool _closed = false;

  @override
  Future<SessionListSnapshot> listSessions() =>
      Future.value(SessionListSnapshot(
          sessions: _closed ? const [] : [_snapshot]));

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) {
    if (sessionId != _snapshot.sessionId) {
      return Future.error(
        Exception('pollSession: unknown sessionId "$sessionId"'),
      );
    }
    return Future.value(_snapshot);
  }

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) {
    final closed = sessionId == _snapshot.sessionId;
    if (closed) {
      // Mark closed so a subsequent listSessions is empty (the rail
      // returns to the empty state after leave, mirroring the real close).
      _closed = true;
    }
    return Future.value(
        CloseSessionResult(sessionId: sessionId, closed: closed));
  }
}

SessionSnapshot _session({required String sessionId, required String peer}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peer,
      state: 'ready',
      path: 'direct',
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

// Pumps MoshApp (owns appRouter) inside a ProviderScope overriding
// gatewayProvider, at the given surface size. appRouter is process-global,
// so the test navigates it via appRouter.go('/sessions') before pumping so
// the rail is the initial visible branch.
Future<void> _pumpApp(
  WidgetTester tester, {
  required Gateway gateway,
  required Size physical,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Reset the process-global router to the rail so a prior test's location
  // does not leak in (appRouter is shared across tests in this file).
  appRouter.go(AppRoutes.sessions);
  await tester.pumpWidget(ProviderScope(
    overrides: [gatewayProvider.overrideWithValue(gateway)],
    child: const MoshApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'desktop (1200x900): rail + welcome pane render side-by-side; '
      'tapping a DM row swaps the chat pane while the rail STAYS', (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'alice-1', peer: 'Alice'));

    await _pumpApp(tester, gateway: gw, physical: const Size(1200, 900));

    // Desktop two-pane: the rail (SessionsScreen) AND the welcome pane
    // (ChatPaneWelcome) BOTH render -- the parity gap (rail stays beside
    // the chat even when no chat is open).
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    // Tap the Alice DM row. On desktop the rail STAYS and the chat pane
    // swaps to DmScreen.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    // The rail is STILL mounted on desktop (the parity invariant).
    expect(find.byType(SessionsScreen), findsOneWidget);
    // The welcome pane was replaced by the DM in the chat branch.
    expect(find.byType(ChatPaneWelcome), findsNothing);
  });

  testWidgets(
      'desktop (1200x900): tapping the titlebar "Peer status" button '
      'mounts PeerStatusDrawer and the close button unmounts it',
      (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'carol-1', peer: 'Carol'));

    await _pumpApp(tester, gateway: gw, physical: const Size(1200, 900));

    // No drawer before the titlebar button is tapped.
    expect(find.byType(PeerStatusDrawer), findsNothing);

    // Tap the shared desktop titlebar's "Peer status" button (its visible
    // text is l.peerStatusTitle -- the same locator style the existing
    // cases use via find.text). At this point the drawer is closed, so
    // "Peer status" resolves to exactly the titlebar button.
    await tester.tap(find.text('Peer status'));
    await tester.pumpAndSettle();

    // The shell flipped its _showPeerStatus and rebuilt the Stack, so the
    // Positioned.fill PeerStatusDrawer is now mounted over the whole
    // shell (rail + chat). Before the fix this assertion FAILED: the
    // titlebar owned the toggle, the shell never rebuilt, the tap no-
    // oped.
    expect(find.byType(PeerStatusDrawer), findsOneWidget);

    // Close via the drawer header's close IconButton (tooltip
    // l.closePeerStatus = "Close peer status" -- unique, so it does not
    // collide with the welcome pane or rail).
    await tester.tap(find.byTooltip('Close peer status'));
    await tester.pumpAndSettle();

    // The shell flipped _showPeerStatus back to false and the drawer
    // unmounted.
    expect(find.byType(PeerStatusDrawer), findsNothing);
  });

  testWidgets(
      'mobile (400x800): rail renders ALONE; tapping a DM row swaps to '
      'DmScreen and the rail is GONE; leaving returns to the rail',
      (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'bob-1', peer: 'Bob'));

    await _pumpApp(tester, gateway: gw, physical: const Size(400, 800));

    // Mobile single-pane: the rail renders ALONE (no welcome pane -- the
    // chat branch is offstage).
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsNothing);

    // Tap the Bob DM row. On mobile the chat REPLACES the rail (rail gone).
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    expect(find.byType(SessionsScreen), findsNothing);

    // Leave the DM (the DM screen's leave confirm closes the session +
    // context.go('/sessions')). Tap the close IconButton (Icons.close) +
    // confirm. The rail returns.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(DmScreen), findsNothing);
  });
}
