// Shell tests pinning the two-pane StatefulShellRoute. The shell
// (mosh_shell.dart) lays
// out the rail branch (A) + chat branch (B) side-by-side on desktop (rail
// ALWAYS visible beside the chat) and as a single pane on mobile (rail OR
// chat). These tests pin both layouts so a regression that re-flattens
// the routes (rail disappears while reading a DM) fails loudly.
//
// The tests pump the real MoshApp through shell_harness.dart, seeded with
// one DM session (peer display name 'Alice' / 'Bob'), at a surface width
// isMobileBreakpoint (MediaQuery.sizeOf, width <= 580) reads.
//
// Cases:
//   1. Desktop (1200x900): /sessions shows the rail (SessionsScreen) AND
//      the welcome pane (ChatPaneWelcome) side-by-side. Tapping the DM row
//      swaps the chat pane to DmScreen while the rail STAYS visible.
//   2. Mobile (400x800): /sessions shows the rail ALONE (no welcome pane).
//      Tapping the DM row swaps to DmScreen and the rail is GONE. Leaving
//      the DM (close + confirm) returns to the rail.
//   3. Desktop (1200x900): tapping the shared titlebar's "Connection status"
//      button mounts the shell-level PeerStatusDrawer (Positioned.fill
//      over rail + chat); tapping the drawer's close button unmounts it.
//      Regression guard for the titlebar-owned-_showPeerStatus bug (the
//      shell never rebuilt when the titlebar flipped its private toggle,
//      so the tap silently no-opped).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/chat_create_step.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/new_session_panel.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'shell_harness.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/routing/mosh_shell.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';

// The start menu title shares its label with the rail's start button.
Finder _onboardTitle() => find.descendant(
      of: find.byType(StartMenu),
      matching: find.text('Start a conversation'),
    );

void main() {
  testWidgets(
      'desktop (1200x900): rail + welcome pane render side-by-side; '
      'tapping a DM row swaps the chat pane while the rail STAYS',
      (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'alice-1', peer: 'Alice')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));

    // Desktop two-pane: the rail (SessionsScreen) AND the welcome pane
    // (ChatPaneWelcome) BOTH render (the rail stays beside
    // the chat even when no chat is open).
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    // Tap the Alice DM row. On desktop the rail STAYS and the chat pane
    // swaps to DmScreen.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(DmScreen), findsOneWidget);
    // The rail is STILL mounted on desktop (the layout invariant).
    expect(find.byType(SessionsScreen), findsOneWidget);
    // The welcome pane was replaced by the DM in the chat branch.
    expect(find.byType(ChatPaneWelcome), findsNothing);
  });

  testWidgets(
      'desktop (1200x900): tapping the titlebar "Connection status" button '
      'mounts PeerStatusDrawer and the close button unmounts it',
      (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'carol-1', peer: 'Carol')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));

    // No drawer before the titlebar button is tapped.
    expect(find.byType(PeerStatusDrawer), findsNothing);

    await tester.tap(find.text('Carol'));
    await tester.pumpAndSettle();

    // The selected conversation's status opens diagnostics on every layout.
    await tester.tap(find.byTooltip('Connection status').first);
    await tester.pumpAndSettle();

    // The shell flipped its _showPeerStatus and rebuilt the Stack, so the
    // Positioned.fill PeerStatusDrawer is now mounted over the whole
    // shell (rail + chat). Before the fix this assertion FAILED: the
    // titlebar owned the toggle, the shell never rebuilt, the tap no-
    // oped.
    expect(find.byType(PeerStatusDrawer), findsOneWidget);

    // Close via the drawer header's close IconButton (tooltip
    // l.closePeerStatus = "Close connection status" -- unique, so it does not
    // collide with the welcome pane or rail).
    await tester.tap(find.byTooltip('Close connection status'));
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
      ..seedSessions([shellSession(sessionId: 'bob-1', peer: 'Bob')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(400, 800));

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
    // desktop-only; the leave entry point is
    // the mobile kebab menu's "Delete chat" item. Open the kebab
    // (Icons.more_vert, ChatHeaderMenu's action-menu trigger), tap
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
  // chat pane while the rail STAYS mounted (the layout invariant). Before
  // this fix, close routed to /sessions on both surfaces -- branch A
  // activated and branch B kept the stale DmScreen mounted, so the inline
  // welcome never re-showed after a close. The mobile path is pinned by
  // the mobile case above (close -> rail returns).
  testWidgets(
      'desktop (1200x900): closing a DM routes to /chat so the inline '
      'NewSessionPanel reappears while the rail STAYS mounted', (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'frank-1', peer: 'Frank')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));

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
    await tester.tap(find.byTooltip('More chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
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
  // inline while the rail stays mounted.
  testWidgets(
      'desktop (1200x900): ChatPaneWelcome embeds NewSessionPanel inline; '
      'tapping the Chat tile switches the inline step (no routing); Back '
      'returns to the menu', (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'dave-1', peer: 'Dave')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));

    // The welcome pane renders beside the rail (chat branch preloaded).
    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    // Desktop embeds NewSessionPanel, whose menu page is StartMenu: the
    // hero title "Start a conversation" and the four cards.
    expect(find.byType(StartMenu), findsOneWidget);
    expect(_onboardTitle(), findsOneWidget);
    expect(find.text('Start a private chat'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);

    // The bare EmptyState CTA is GONE on desktop (mobile-only now).
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
    expect(find.text('Welcome to Mosh.'), findsNothing);
    expect(
        find.text(
            'Create an invite or paste one to start your first encrypted conversation.'),
        findsNothing);

    // Tap the Chat card. NewSessionPanel switches to the chat step in
    // place (no routing): the step title and a Back button render while
    // the rail stays.
    final location = appRouter.routeInformationProvider.value.uri.path;
    await tester.tap(find.text('Start a private chat'));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, location);

    // The menu card with the same text is offstage (skipOffstage default
    // skips it), so this finds exactly the visible step title.
    final chatTitle =
        AppLocalizations.of(tester.element(find.byType(ChatPaneWelcome)))!
            .onboardTileChatTitle;
    expect(find.text(chatTitle), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsOneWidget);

    // Back returns to the menu. The chat step goes offstage, so
    // find.byType skips it; the menu card re-shows its title, so the type
    // check is the "step gone" signal.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(_onboardTitle(), findsOneWidget);
    expect(find.byType(ChatCreateStep), findsNothing);
  });

  // Mobile ChatPaneWelcome uses the same NewSessionPanel as desktop. This
  // pins the one-tap SessionRail New flow: the full panel is inline.
  testWidgets('mobile (400x800): ChatPaneWelcome embeds NewSessionPanel inline',
      (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'erin-1', peer: 'Erin')]);

    await pumpShellApp(tester, gateway: gw, physical: const Size(400, 800));

    // Mobile single-pane: the chat branch is offstage (rail is active),
    // so navigate to /chat to mount ChatPaneWelcome as the active branch.
    appRouter.go(AppRoutes.chat);
    await tester.pumpAndSettle();

    expect(find.byType(ChatPaneWelcome), findsOneWidget);

    expect(find.byType(NewSessionPanel), findsOneWidget);
    expect(find.byType(StartMenu), findsOneWidget);
    expect(_onboardTitle(), findsOneWidget);
    expect(find.text('Start a private chat'), findsOneWidget);
  });

  // The DM is a pushed route in the chat branch; its ModalBarrier blocks the
  // semantics of everything painted before it in the shell.
  testWidgets(
      'desktop (1200x900): with a DM open, screen readers still reach the '
      'rail and the titlebar', (tester) async {
    final handle = tester.ensureSemantics();
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'gina-1', peer: 'Gina')]);
    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));

    await tester.tap(find.text('Gina'));
    await tester.pumpAndSettle();
    expect(find.byType(DmScreen), findsOneWidget);

    expect(
        find.bySemanticsLabel(RegExp('Start a conversation')), findsOneWidget);
    expect(find.semantics.byLabel(RegExp('Connection status')), findsOne);
    handle.dispose();
  });

  testWidgets(
      'desktop (1200x900): the shell drawer words a failed read for people, '
      'not with the runtime message', (tester) async {
    final gw = ScriptableGateway()
      ..seedSessions([shellSession(sessionId: 'hana-1', peer: 'Hana')])
      ..failAlways(
        GatewayMethod.poll,
        error: const ConversationBridgeError(
          kind: ConversationBridgeErrorKind.unavailable,
          message: 'moss: socket closed',
        ),
      );
    await pumpShellApp(tester, gateway: gw, physical: const Size(1200, 900));
    await tester.tap(find.text('Hana'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Connection status').first);
    await tester.pumpAndSettle();

    Finder inDrawer(String text) => find.descendant(
        of: find.byType(PeerStatusDrawer), matching: find.textContaining(text));
    expect(inDrawer('Mosh could not reach the network.'), findsWidgets);
    expect(inDrawer('moss: socket closed'), findsNothing);
  });
}
