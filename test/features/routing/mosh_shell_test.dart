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
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_screen.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
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

  // Desktop close-flow (atomic #9, NewSessionPanel-inline epic): on desktop
  // the DM screen's `_leave` routes to /chat (branch B initialLocation)
  // instead of /sessions, so the inline NewSessionPanel reappears in the
  // chat pane while the rail STAYS mounted (the parity invariant). Before
  // this fix, close routed to /sessions on both surfaces -- branch A
  // activated and branch B kept the stale DmScreen mounted, so the inline
  // welcome never re-showed after a close. The mobile path is pinned by
  // the mobile case above (close -> rail returns).
  testWidgets(
      'desktop (1200x900): closing a DM routes to /chat so the inline '
      'NewSessionPanel reappears while the rail STAYS mounted',
      (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'frank-1', peer: 'Frank'));

    await _pumpApp(tester, gateway: gw, physical: const Size(1200, 900));

    // Open Frank's DM. Desktop two-pane: rail STAYS, chat pane swaps to
    // the DM (the welcome pane is replaced).
    await tester.tap(find.text('Frank'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(NewSessionPanel), findsNothing);

    // Leave the DM (Icons.close -> ConfirmDialog -> "Delete chat"). On
    // desktop the screen's _leave routes to /chat, so branch B swaps back
    // to its initialLocation -- the inline NewSessionPanel reappears.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();

    // The stale chat unmounts; the inline NewSessionPanel re-shows in the
    // chat pane (the desktop close->inline-panel behavior this atomic
    // pins).
    expect(find.byType(DmScreen), findsNothing);
    expect(find.byType(NewSessionPanel), findsOneWidget);
    // The rail stays mounted on desktop (it was always mounted).
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  // Desktop ChatPaneWelcome Start CTA (React EmptyState parity,
  // ActiveChatPanes.tsx:407-418): the desktop right-pane welcome is no
  // longer the bare EmptyState CTA. React renders the full NewSessionPanel
  // (OnboardMenu) INLINE in the chat-pane when no conversation is open
  // (private-dm-screen.tsx:325-343); the bare CTA is mobile-only now. The
  // desktop branch embeds the same OnboardMenu the OnboardingScreen uses,
  // so the welcome pane renders the menu's identity chip -> head -> Start
  // tiles -> Join tiles -> Advanced/About. Tapping the Chat tile routes to
  // /chat-create (ChatCreateScreen mounts) -- the same route the onboarding
  // Chat tile uses. The chat branch is preloaded (app_router.dart
  // preload: true) so the welcome pane renders side-by-side with the rail
  // at >= 900 wide even though /sessions is the active branch.
  //
  // Atomic #8 inlined the steps (React NewSessionPanel parity,
  // NewSessionPanel.tsx:18-67): the desktop welcome now embeds
  // NewSessionPanel (owns the OnboardStep state + an IndexedStack that
  // keeps every step mounted). Tapping the Chat tile NO LONGER routes to
  // /chat-create -- it switches the inline step to ChatCreateStep wrapped
  // in OnboardStepBody (title + Back). Back returns to the menu. The rail
  // stays mounted throughout (no routing). This case pins the inline
  // switch + the back round-trip; the mobile case below pins the bare CTA
  // still routes.
  testWidgets(
      'desktop (1200x900): ChatPaneWelcome embeds NewSessionPanel inline; '
      'tapping the Chat tile switches the inline step (no routing); Back '
      'returns to the menu', (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'dave-1', peer: 'Dave'));

    await _pumpApp(tester, gateway: gw, physical: const Size(1200, 900));

    // The welcome pane renders beside the rail (chat branch preloaded).
    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    // Desktop embeds NewSessionPanel, whose step=menu child is OnboardMenu
    // (React NewSessionPanel parity). The menu renders the onboard head
    // (onboardTitle "Start a conversation") + the four tiles (Start:
    // chat/group, Join: join/channel).
    expect(find.byType(OnboardMenu), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);

    // The bare EmptyState CTA is GONE on desktop (mobile-only now).
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
    expect(find.text('Welcome to Mosh.'), findsNothing);
    expect(find.text('Create an invite or paste one to start your first encrypted conversation.'),
        findsNothing);

    // Tap the Chat tile (onboardTileChatTitle "New private chat"). The
    // desktop NewSessionPanel switches its IndexedStack to the chat step
    // INLINE (no context.go): ChatCreateStep wrapped in OnboardStepBody
    // renders the step title (l.onboardTileChatTitle) + a Back button.
    // ChatCreateScreen does NOT mount -- the step is inline, the rail
    // stays, no routing happened.
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();

    // No routing: ChatCreateScreen does NOT mount (the step is inline).
    expect(find.byType(ChatCreateScreen), findsNothing);
    // The chat step body (ChatCreateStep) is now the active IndexedStack
    // child, so it is on-stage. The menu tile carrying the same
    // "New private chat" text is offstage (skipOffstage default skips it),
    // so find.text(l.onboardTileChatTitle) resolves to exactly the visible
    // step title (OnboardStepBody headlineSmall).
    final chatTitle = AppLocalizations.of(
            tester.element(find.byType(ChatPaneWelcome)))!
        .onboardTileChatTitle;
    expect(find.text(chatTitle), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsOneWidget);

    // Back (l.onboardBack "Back") returns the IndexedStack to step=menu.
    // The menu re-renders (onboardTitle "Start a conversation" findsOne).
    // The chat step body (ChatCreateStep) goes offstage inside the
    // IndexedStack, so find.byType skips it (skipOffstage default). The
    // menu tile "New private chat" re-shows, so find.text(chatTitle) is
    // NOT usable as the "step gone" signal -- the type check is.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsNothing);
  });

  // Mobile ChatPaneWelcome CTA (React EmptyState parity,
  // ActiveChatPanes.tsx:407-418): the mobile chat-pane welcome keeps the
  // bare CTA (icon + title + body + start button) that atomic #3 replaced
  // with the inline OnboardMenu on desktop. The mobile step screens stay
  // full-screen (the parity-correct mobile path for now), so tapping the
  // CTA routes to /chat-create (ChatCreateScreen mounts). This pins the
  // mobile path is preserved after the desktop inline-menu change.
  testWidgets(
      'mobile (400x800): ChatPaneWelcome keeps the bare start CTA; tapping '
      'it routes to /chat-create', (tester) async {
    final gw = _SeededGateway(
        _session(sessionId: 'erin-1', peer: 'Erin'));

    await _pumpApp(tester, gateway: gw, physical: const Size(400, 800));

    // Mobile single-pane: the chat branch is offstage (rail is active),
    // so navigate to /chat to mount ChatPaneWelcome as the active branch.
    appRouter.go(AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    // Mobile keeps the React EmptyState order 1:1: icon -> title -> body ->
    // start CTA button. No OnboardMenu inline on mobile.
    expect(find.byIcon(Icons.chat_outlined), findsOneWidget);
    expect(find.text('Welcome to Mosh.'), findsOneWidget);
    expect(find.text('Create an invite or paste one to start your first encrypted conversation.'),
        findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);
    expect(find.byType(OnboardMenu), findsNothing);

    // Tap the start CTA. The router's onStart closure does
    // context.go(AppRoutes.chatCreate), mounting ChatCreateScreen. Mobile
    // still routes (the mobile branch of ChatPaneWelcome is unchanged).
    await tester.tap(find.text('New private chat'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatCreateScreen), findsOneWidget);
  });
}
