// S4.6: widget test for FingerprintConfirmScreen. Overrides
// activeSessionProvider (FutureProvider.family) with a canned AsyncData so the
// test needs neither the gateway nor the Rust runtime. Asserts the fingerprint
// renders, the confirm button is tappable, and tapping flips to confirmed.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/fingerprint/fingerprint_confirm_screen.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/state/session_providers.dart';
import '../../support/pump.dart';

SessionSnapshot _snapshot() => SessionSnapshot(
      sessionId: 'test-session',
      meshId: 'm',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: 'peer',
      state: DmSessionState.pending,
      transport: PeerTransport.none,
      inviteUri: null,
      fingerprint: 'AABBCCDDEEFF0011',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

void main() {
  testWidgets('renders fingerprint, confirm tap flips to confirmed',
      (tester) async {
    await pumpScreen(
        tester, FingerprintConfirmScreen(sessionId: 'test-session'),
        overrides: [
          activeSessionProvider.overrideWith(
            (ref, id) => Future.value(_snapshot()),
          ),
        ]);

    expect(find.text('AABBCCDDEEFF0011'), findsOneWidget);
    expect(find.text('Confirm fingerprint'), findsOneWidget);
    expect(find.textContaining('Verify out-of-band'), findsOneWidget);

    await tester.tap(find.text('Confirm fingerprint'));
    await tester.pumpAndSettle();

    expect(find.text('Fingerprint confirmed'), findsOneWidget);
    expect(find.text('Confirm fingerprint'), findsNothing);
  });
}
