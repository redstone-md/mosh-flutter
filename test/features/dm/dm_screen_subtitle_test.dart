// Widget tests for the DmScreen AppBar subtitle parity -- the 1-в-1 port
// of React's ActiveDmChat header subtitle (ActiveChatPanes.tsx L86-90):
//   subtitle={ props.confirmed
//       ? `MLS ${props.session.state} · fingerprint confirmed`
//       : `MLS ${props.session.state} · fingerprint unverified` }
// Flutter 3.44 AppBar has no `subtitle:` slot, so the DmScreen AppBar
// `title:` is a two-line Column (peer display name + bodySmall subtitle),
// mirroring `group_screen_header.dart`'s established two-line pattern. The
// subtitle text is the new `dmSubtitleConfirmed`/`dmSubtitleUnverified` ARB
// keys (`MLS {state} · fingerprint {confirmed|unverified}`), branched on the
// local `_confirmedFingerprints` set membership (the same `confirmed`
// boolean that drives the FingerprintBadge).
//
// Two cases, both seeded with a SessionSnapshot whose `state` is "Active"
// and `fingerprint` is non-empty so the badge is tappable:
//   1. Before any confirm: subtitle renders "MLS Active · fingerprint
//      unverified" (the `confirmed=false` branch).
//   2. After tapping the FingerprintBadge (which fires `_confirmFingerprint`
//      -> adds the sessionId to `_confirmedFingerprints` -> `confirmed`
//      flips true): subtitle renders "MLS Active · fingerprint confirmed".
//
// Mirrors the seed/override idiom of `dm_screen_close_flow_test.dart`
// (override `activeSessionProvider` so the native cdylib is not involved).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import 'package:mosh/src/features/dm/fingerprint_badge.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// A SessionSnapshot seeded with `state: "Active"` and a non-empty
/// `fingerprint` so the FingerprintBadge renders and is tappable (the badge
/// returns a SizedBox.shrink when `fingerprint` is empty, and `onConfirm`
/// is disabled when `confirmed` is already true -- neither applies here
/// since `confirmed` starts false).
SessionSnapshot _snapshot({required String sessionId, required String peerName}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peerName,
      state: 'Active',
      path: 'direct',
      relayReady: null,
      inviteUri: null,
      fingerprint: 'fp-peer-1234',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(
  WidgetTester tester,
  FakeGateway gateway, {
  required String sessionId,
  required String peerName,
}) async {
  // Use the real appRouter so navigation hooks do not throw (mirrors
  // `dm_screen_close_flow_test.dart`).
  final router = GoRouter(
    initialLocation: AppRoutes.dmFor(sessionId),
    routes: appRouter.configuration.routes,
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gatewayProvider.overrideWithValue(gateway),
      activeSessionProvider(sessionId).overrideWith(
        (ref) async => _snapshot(sessionId: sessionId, peerName: peerName),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const sessionId = 'dm-subtitle-1';
  const peerName = 'juno-phone';

  testWidgets(
      'subtitle renders "MLS Active · fingerprint unverified" before confirm',
      (tester) async {
    final gateway = FakeGateway();
    await _pump(tester, gateway, sessionId: sessionId, peerName: peerName);

    // React ActiveChatPanes.tsx L88-89 unverified branch, with state="Active".
    expect(find.text('MLS Active · fingerprint unverified'), findsOneWidget);
    // The peer display name is the first line of the two-line Column title.
    expect(find.text(peerName), findsOneWidget);
    // The confirmed branch must NOT render yet.
    expect(find.text('MLS Active · fingerprint confirmed'), findsNothing);
  });

  testWidgets(
      'subtitle flips to "MLS Active · fingerprint confirmed" after tapping '
      'the FingerprintBadge', (tester) async {
    final gateway = FakeGateway();
    await _pump(tester, gateway, sessionId: sessionId, peerName: peerName);

    // Unverified subtitle renders first.
    expect(find.text('MLS Active · fingerprint unverified'), findsOneWidget);

    // Tap the FingerprintBadge (React `onClick={confirmed ? undefined :
    // onConfirm}` -- here `confirmed` is false, so the tap fires
    // `_confirmFingerprint`, adding the sessionId to the
    // `_confirmedFingerprints` set and flipping `confirmed` -> true).
    await tester.tap(find.byType(FingerprintBadge));
    await tester.pumpAndSettle();

    // The subtitle now renders the confirmed branch.
    expect(find.text('MLS Active · fingerprint confirmed'), findsOneWidget);
    expect(find.text('MLS Active · fingerprint unverified'), findsNothing);
    expect(find.byType(DmScreen), findsOneWidget);
  });
}
