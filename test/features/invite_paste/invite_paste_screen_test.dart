// S4.5: widget test for the Invite Paste screen. Pumps it in a ProviderScope
// + localized MaterialApp.router (the step's Back button uses context.go),
// drives live detection, and asserts:
//   - the OnboardStepFrame title + body render (no AppBar),
//   - the 3-state detection badge (neutral / ok / bad) flips with input,
//   - the Connect button is enabled for every detected kind (dm + group +
//     org -- all three have a wired Gateway seam),
//   - tapping Connect on a DM invite calls bridge.acceptInvite,
//   - tapping Connect on a group invite calls bridge.joinGroup and
//     navigates to the group screen,
//   - tapping Connect on an org bundle calls bridge.joinOrg and navigates
//     to the sessions list (orgs are a container, not a chat).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/features/conversation/group_screen.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import '../../support/scriptable_bridge.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import '../../support/pump.dart';

void main() {
  Future<void> pumpPasteStep(
    WidgetTester tester,
    BridgeFacade bridge, {
    String initialLocation = AppRoutes.join,
  }) =>
      pumpRoute(tester, initialLocation,
          overrides: [bridgeFacadeProvider.overrideWithValue(bridge)]);
  testWidgets(
      'renders the OnboardStepFrame title (no AppBar) and a neutral badge on empty',
      (tester) async {
    await pumpPasteStep(tester, ScriptableBridge());

    // The frame renders the join step title (h1), not an AppBar.
    expect(find.text('Join with a link'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    // The body paragraph renders.
    expect(find.textContaining('Paste a mosh:// invite link'), findsOneWidget);
    // Empty -> neutral badge: the "waiting" label, no check icon, Connect
    // disabled (onPressed null).
    expect(find.text('Waiting for a mosh:// link…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('dm detection shows the ok badge and enables Connect',
      (tester) async {
    await pumpPasteStep(tester, ScriptableBridge());

    await tester.enterText(find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    // ok badge: the "private chat invite detected" label + a check icon.
    expect(find.text('Private chat invite detected'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // DM -> Connect enabled.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('unknown detection shows the bad badge and disables Connect',
      (tester) async {
    await pumpPasteStep(tester, ScriptableBridge());

    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    // bad badge: the canonical "bad" label, NO check icon, Connect disabled.
    expect(
        find.text('That does not look like a mosh:// invite'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets(
      'group detection shows the ok badge and ENABLES Connect; tapping navigates to the group screen',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpPasteStep(tester, bridge);

    // Valid group invite (mosh://group, 32-hex fingerprint).
    await tester.enterText(find.byType(TextField),
        'mosh://group?mesh=7x9v&group=drift-team#fp=91A4D2C877B091A4D2C877B091A4D2C8');
    await tester.pump();
    // ok badge: the "group invite detected" label + a check icon (group is a
    // detected kind, so the badge is green/ok 1-в-1 with React).
    expect(find.text('Group invite detected'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // group join is wired (slice-3 seam): Connect is ENABLED.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    // Tapping Connect calls the bridge's joinGroup (canned GroupSnapshot with
    // groupId parsed from the invite URI's `group=` param) and navigates to
    // the group screen (1-в-1 with React setActive({type:"group", id})).
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(GroupScreen), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsNothing);
    expect(bridge.countOf(BridgeMethod.listGroups), 2);
  });

  testWidgets(
      'org detection shows the ok badge and ENABLES Connect; tapping navigates to the sessions list',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpPasteStep(tester, bridge);

    // Valid org bundle: mosh://org + mesh= + name= + #org=<64 hex>.
    await tester.enterText(
        find.byType(TextField),
        'mosh://org?mesh=7x9v&name=drift-collective#org='
        '91a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4');
    await tester.pump();
    // ok badge: the "organization bundle detected" label + a check icon.
    expect(find.text('Organization bundle detected'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // org join is wired (slice-3 seam): Connect is ENABLED.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    // Tapping Connect calls the bridge's joinOrg (canned OrgSnapshot). React's
    // joinOrg does NOT navigate to a dedicated org screen -- it leaves setup
    // + refreshes the orgs list, landing the user back on the rail. Flutter
    // has no org screen, so the faithful action is AppRoutes.sessions.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(SessionsScreen), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsNothing);
    expect(bridge.countOf(BridgeMethod.listOrgs), 2);
  });

  testWidgets('a failed group join does not refresh groups or navigate',
      (tester) async {
    const message = 'Group runtime offline';
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.joinGroup, error: message);
    await pumpPasteStep(tester, bridge);

    await tester.enterText(find.byType(TextField),
        'mosh://group?mesh=7x9v&group=drift-team#fp=91A4D2C877B091A4D2C877B091A4D2C8');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listGroups), 0);
  });

  testWidgets('a failed org join does not refresh orgs or navigate',
      (tester) async {
    const message = 'Org runtime offline';
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.joinOrg, error: message);
    await pumpPasteStep(tester, bridge);

    await tester.enterText(
        find.byType(TextField),
        'mosh://org?mesh=7x9v&name=drift-collective#org='
        '91a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4d2c877b091a4');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listOrgs), 0);
  });

  testWidgets('tapping Connect on a DM invite calls bridge.acceptInvite',
      (tester) async {
    final bridge = ScriptableBridge();
    await pumpPasteStep(tester, bridge);

    await tester.enterText(find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Accepted session:'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listSessions), 2);
  });

  // The bridge throws the generated ConversationBridgeError (ticket 17); the
  // step words the inline error by its kind. `invalidInput` is the one kind
  // that keeps the runtime's detail, because "fix the paste" needs it.
  testWidgets('a rejected paste is worded by the bridge error\'s kind',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.invalidInput,
      message: 'invite fingerprint does not match',
    );
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.acceptInvite, error: error);
    await pumpPasteStep(tester, bridge);

    await tester.enterText(find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final l =
        AppLocalizations.of(tester.element(find.byType(InvitePasteScreen)))!;
    expect(
        find.text(l.chatActionErrorInvalidInput(error.message)), findsOneWidget);
    expect(find.text(error.message), findsNothing);
    expect(find.byType(InvitePasteScreen), findsOneWidget);
  });

  testWidgets('a failed DM accept does not initialize or refresh sessions',
      (tester) async {
    const message = 'DM runtime offline';
    final bridge = ScriptableBridge()
      ..failAlways(BridgeMethod.acceptInvite, error: message);
    await pumpPasteStep(tester, bridge);

    await tester.enterText(find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('Accepted session:'), findsNothing);
    expect(bridge.countOf(BridgeMethod.listSessions), 0);
  });

  testWidgets('Back returns to the onboarding menu', (tester) async {
    await pumpPasteStep(tester, ScriptableBridge());

    // The frame's Back affordance reads the localized "Back" label.
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsNothing);
  });

  testWidgets(
      'group detection badge stays ok and Connect stays enabled across edits',
      (tester) async {
    await pumpPasteStep(tester, ScriptableBridge());

    // Start empty (neutral), enter a group (ok badge, ENABLED Connect),
    // then garbage (bad badge, disabled Connect).
    expect(find.text('Waiting for a mosh:// link…'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.enterText(find.byType(TextField),
        'mosh://group?mesh=7x9v&group=drift-team#fp=91A4D2C877B091A4D2C877B091A4D2C8');
    await tester.pump();
    expect(find.text('Group invite detected'), findsOneWidget);
    // group join is wired (slice-3): Connect is ENABLED for group.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    expect(
        find.text('That does not look like a mosh:// invite'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    // Back to a DM invite: ok badge, Connect enabled again.
    await tester.enterText(find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    expect(find.text('Private chat invite detected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
