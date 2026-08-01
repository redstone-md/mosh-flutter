// S4.5: widget test for the Invite Paste screen. Pumps it in a ProviderScope
// + localized MaterialApp.router (the step's Back button uses context.go),
// drives live detection, and asserts:
//   - the OnboardStepFrame title + body render (no AppBar),
//   - the 3-state detection badge (neutral / ok / bad) flips with input,
//   - the Connect button is DM-only: enabled for a DM detection, DISABLED
//     for a group detection (group/org join needs Gateway methods that do
//     not exist yet -- deferred),
//   - tapping Connect on a DM invite calls gateway.acceptInvite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/features/onboarding/onboarding_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  Future<GoRouter> pumpScreen(
    WidgetTester tester,
    Gateway gateway, {
    String initialLocation = AppRoutes.join,
  }) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: appRouter.configuration.routes,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [gatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets(
      'renders the OnboardStepFrame title (no AppBar) and a neutral badge on empty',
      (tester) async {
    await pumpScreen(tester, FakeGateway());

    // The frame renders the join step title (h1), not an AppBar.
    expect(find.text('Join with a link'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    // The body paragraph renders.
    expect(
        find.textContaining('Paste a mosh:// invite link'), findsOneWidget);
    // Empty -> neutral badge: the "waiting" label, no check icon, Connect
    // disabled (onPressed null).
    expect(find.text('Waiting for a mosh:// link…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('dm detection shows the ok badge and enables Connect', (tester) async {
    await pumpScreen(tester, FakeGateway());

    await tester.enterText(
        find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    // ok badge: the "private chat invite detected" label + a check icon.
    expect(find.text('Private chat invite detected'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // DM -> Connect enabled.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('unknown detection shows the bad badge and disables Connect', (tester) async {
    await pumpScreen(tester, FakeGateway());

    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    // bad badge: the canonical "bad" label, NO check icon, Connect disabled.
    expect(find.text('That does not look like a mosh:// invite'),
        findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets(
      'group detection shows the ok badge but DISABLES Connect (join deferred)',
      (tester) async {
    await pumpScreen(tester, FakeGateway());

    // Valid group invite (mosh://group, 32-hex fingerprint).
    await tester.enterText(
        find.byType(TextField),
        'mosh://group?mesh=7x9v&group=drift-team#fp=91A4D2C877B091A4D2C877B091A4D2C8');
    await tester.pump();
    // ok badge: the "group invite detected" label + a check icon (group is a
    // detected kind, so the badge is green/ok 1-в-1 with React).
    expect(find.text('Group invite detected'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // DM-only Connect (see file header): group join is deferred, so the
    // Connect button is DISABLED even though the badge is ok.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('tapping Connect on a DM invite calls gateway.acceptInvite',
      (tester) async {
    await pumpScreen(tester, FakeGateway());

    await tester.enterText(
        find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Accepted session:'), findsOneWidget);
  });

  testWidgets('Back returns to the onboarding menu', (tester) async {
    await pumpScreen(tester, FakeGateway());

    // The frame's Back affordance reads the localized "Back" label.
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Routing returned to '/' (onboarding): the menu screen reappears.
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(InvitePasteScreen), findsNothing);
  });

  testWidgets('group detection badge stays ok and Connect stays disabled across edits',
      (tester) async {
    await pumpScreen(tester, FakeGateway());

    // Start empty (neutral), enter a group (ok badge, disabled Connect),
    // then garbage (bad badge, disabled Connect).
    expect(find.text('Waiting for a mosh:// link…'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.enterText(
        find.byType(TextField),
        'mosh://group?mesh=7x9v&group=drift-team#fp=91A4D2C877B091A4D2C877B091A4D2C8');
    await tester.pump();
    expect(find.text('Group invite detected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    expect(find.text('That does not look like a mosh:// invite'),
        findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    // Back to a DM invite: ok badge, Connect enabled again.
    await tester.enterText(
        find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    expect(find.text('Private chat invite detected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
