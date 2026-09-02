// Shell tests pinning the two-pane StatefulShellRoute -- the React
// private-dm-screen desktop-body parity gap (private-dm-screen.tsx:243-343
// + use-conversation-rail-state.ts:1-38). The shell (mosh_shell.dart) lays
// out the rail branch (A) + chat branch (B) side-by-side on desktop (rail
// ALWAYS visible beside the chat) and as a single pane on mobile (rail OR
// chat). These tests pin both layouts so a regression that re-flattens
// the routes (rail disappears while reading a DM) fails loudly.
//
// The tests pump the real MoshApp (which owns the process-global appRouter)
// inside a ProviderScope overriding the two bridge providers with scripted
// doubles sharing one conversation state
// seeded with one DM session
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
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

// Seeded test gateway: listSessions + poll return one DM session
// with the given peer display name, so the rail renders one row AND the DM
// screen resolves without the native cdylib. leave removes the
// seeded session so the leave-flow's context.go('/sessions') returns to an
// empty rail (mirrors the real close).
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

// Pumps MoshApp (owns appRouter) inside a ProviderScope overriding the two
// bridge providers, at the given surface size. appRouter is process-global,
// so the test navigates it via appRouter.go('/sessions') before pumping so
// the rail is the initial visible branch.
Future<void> _pumpApp(
  WidgetTester tester, {
  required ScriptableGateway gateway,
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
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
    ],
    child: const MoshApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'desktop (1200x900): rail + welcome pane render side-by-side; '
      'tapping a DM row swaps the chat pane while the rail STAYS',
      (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'alice-1', peer: 'Alice')]);

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
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'carol-1', peer: 'Carol')]);

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
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'bob-1', peer: 'Bob')]);

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
    // context.go('/sessions')). On MOBILE the standalone close button is
    // desktop-only (React `chat-desktop-only`); the leave entry point is
    // the mobile kebab menu's "Delete chat" item. Open the kebab
    // (Icons.more_vert, ChatHeaderMenu's PopupMenuButton trigger), tap
    // "Delete chat" from the dropdown -> ConfirmDialog -> tap the dialog's
    // "Delete chat" confirm button. The rail returns. (The menu closes
    // when its item is selected, so `find.text('Delete chat')` resolves
    // to exactly one widget at each stage -- menu item, then dialog.)
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
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
      'NewSessionPanel reappears while the rail STAYS mounted', (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'frank-1', peer: 'Frank')]);

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

  // The desktop welcome embeds the full NewSessionPanel. Its steps switch
  // inline while the rail stays mounted, matching React's showSetup branch.
  testWidgets(
      'desktop (1200x900): ChatPaneWelcome embeds NewSessionPanel inline; '
      'tapping the Chat tile switches the inline step (no routing); Back '
      'returns to the menu', (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'dave-1', peer: 'Dave')]);

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
    expect(
        find.text(
            'Create an invite or paste one to start your first encrypted conversation.'),
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
    final chatTitle =
        AppLocalizations.of(tester.element(find.byType(ChatPaneWelcome)))!
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

  // Mobile ChatPaneWelcome uses the same NewSessionPanel as desktop. This
  // pins the one-tap SessionRail New flow: the full panel is inline and the
  // chat-create route is not pushed.
  testWidgets('mobile (400x800): ChatPaneWelcome embeds NewSessionPanel inline',
      (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([_session(sessionId: 'erin-1', peer: 'Erin')]);

    await _pumpApp(tester, gateway: gw, physical: const Size(400, 800));

    // Mobile single-pane: the chat branch is offstage (rail is active),
    // so navigate to /chat to mount ChatPaneWelcome as the active branch.
    appRouter.go(AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.byType(OnboardMenu), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('New private chat'), findsOneWidget);
    expect(find.byType(ChatCreateScreen), findsNothing);
  });
}
