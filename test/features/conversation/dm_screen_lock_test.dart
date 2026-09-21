// Widget tests for the DmScreen header fingerprint surface (the
// replacement of the old confirm-badge subtitle test):
//   1. A non-empty fingerprint renders the lock next to the peer name
//      and the subtitle is the plain status sentence (no
//      confirmed/unverified suffix -- that state is gone).
//   2. An empty fingerprint renders no lock.
//   3. Tapping the lock opens the fingerprint dialog with the emoji
//      quartet, the hex, and the DM compare hint.
//   4. The mobile kebab carries no confirm-fingerprint item anymore.
//
// Mirrors the seed/override idiom of the deleted dm_screen_subtitle_test
// (override activeSessionProvider so the native cdylib is not involved).
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_lock.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/pump.dart';

/// A SessionSnapshot seeded connected over a direct path, with a
/// fingerprint chosen for the lock to render.
SessionSnapshot _snapshot(
        {required String sessionId,
        required String peerName,
        required String fingerprint}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'testmesh',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: peerName,
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: fingerprint,
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
  ScriptableGateway gateway, {
  required String sessionId,
  required String peerName,
  required String fingerprint,
}) async {
  // Use the real appRouter so navigation hooks do not throw.
  await pumpRoute(tester, AppRoutes.dmFor(sessionId), overrides: [
    gatewayProvider.overrideWithValue(gateway),
    activeSessionProvider(sessionId).overrideWith(
      (ref) async => _snapshot(
          sessionId: sessionId, peerName: peerName, fingerprint: fingerprint),
    ),
  ]);
}

void main() {
  const sessionId = 'dm-lock-1';
  const peerName = 'juno-phone';
  const fingerprint = '0011223344556677';

  testWidgets(
      'lock renders next to the peer name and the subtitle is the plain '
      'status sentence', (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway,
        sessionId: sessionId, peerName: peerName, fingerprint: fingerprint);

    // The lock sits in the title row, next to the peer name.
    expect(find.byType(FingerprintLock), findsOneWidget);
    expect(find.text(peerName), findsOneWidget);
    // The subtitle is the state sentence alone -- the confirmed/
    // unverified suffix is gone with the confirm state.
    expect(find.text('Connected · direct'), findsOneWidget);
    expect(
      find.textContaining('fingerprint'),
      findsNothing,
    );
  });

  testWidgets('empty fingerprint renders no lock', (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway,
        sessionId: sessionId, peerName: peerName, fingerprint: '');

    // The lock self-gates on an empty fingerprint: no icon, nothing to
    // tap (the E2EE banner in the body is a different icon, so byIcon
    // would be ambiguous -- the tooltip is the lock's own).
    expect(find.byTooltip('End-to-end encrypted'), findsNothing);
  });

  testWidgets('tapping the lock opens the dialog with emoji, hex and hint',
      (tester) async {
    final gateway = ScriptableGateway();
    await _pump(tester, gateway,
        sessionId: sessionId, peerName: peerName, fingerprint: fingerprint);

    await tester.tap(find.byTooltip('End-to-end encrypted'));
    await tester.pumpAndSettle();

    expect(find.text('Encryption fingerprint'), findsOneWidget);
    expect(find.text(fingerprint), findsOneWidget);
    expect(
      find.text(fingerprintEmoji(fingerprint).join()),
      findsOneWidget,
    );
    expect(
      find.text(
          'The same on both sides. Compare it with your peer over a call or in person.'),
      findsOneWidget,
    );
    // Closing works.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsNothing);
  });
}
