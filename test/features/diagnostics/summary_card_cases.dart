// Widget tests for `SummaryCard`
// (lib/src/features/diagnostics/summary_card.dart). Pumps the card inside a
// localized `MaterialApp` and asserts that the title, state, description and
// all 3 facts render for a ready-tone summary; that the idle copy renders
// for an idle-tone summary; and that an error-tone badge takes the error
// plate.
//
// The summaries are built via the real `diagnosticsSummary` builder so
// the widget test also pins the round-trip from builder -> widget.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations_en.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';
import 'package:mosh/src/features/diagnostics/summary_card.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import '../../support/pump.dart';

MeshInfo _mesh({int peerCount = 1}) => MeshInfo(
      meshId: 'mesh-1',
      listenPort: 0,
      advertisedAddr: '',
      peerCount: peerCount,
      directPeerCount: 0,
      relayedPeerCount: 0,
      relayCapablePeerCount: 0,
      relaySessionCount: 0,
      relayRouteCount: 0,
      knownPeerCount: 0,
      channels: const [],
      natType: 'full-cone',
      supernodeReady: false,
      publicKey: '',
      peerDetails: const [],
    );

SessionSnapshot _readySession() => SessionSnapshot(
      inviteAvailable: false,
      sessionId: 'sess-1',
      meshId: 'mesh-1',
      role: 'inviter',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: _mesh(peerCount: 1),
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

Future<void> _pump(WidgetTester tester, Widget child) =>
    pumpScreen(tester, Scaffold(body: Center(child: child)));

void main() {
  group('SummaryCard - ready tone', () {
    testWidgets('renders title, state, description, and all 3 facts',
        (tester) async {
      final l = AppLocalizationsEn(); // resolved via the test's en locale
      final sum = diagnosticsSummary(
        l: l,
        session: _readySession(),
      );
      await _pump(tester, SummaryCard(summary: sum));

      // Title falls back to peerDisplayName "Alice".
      expect(find.text('Alice'), findsOneWidget);
      // State badge shows the localized ready label ("Connected").
      expect(find.text('Connected'), findsOneWidget);
      // Description is the ready-with-peers copy.
      expect(
        find.text('MLS is ready and Moss sees at least one peer on this mesh.'),
        findsOneWidget,
      );
      expect(find.text('Peers'), findsOneWidget);
      expect(find.text('NAT'), findsOneWidget);
      expect(find.text('Relay'), findsOneWidget);
      // Fact values: peerCount=1, natType=full-cone, relay none.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('full-cone'), findsOneWidget);
      expect(find.text('none'), findsOneWidget);
    });
  });

  group('SummaryCard - idle tone', () {
    testWidgets(
        'renders the idle copy + Waiting state + none/paused/none facts',
        (tester) async {
      final l = AppLocalizationsEn();
      final sum = diagnosticsSummary(l: l, session: null);
      await _pump(tester, SummaryCard(summary: sum));

      expect(find.text('No active session'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(
        find.text(
            'Open a conversation to inspect connection state, peer count, NAT, relay, and events.'),
        findsOneWidget,
      );
      // Fact labels.
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('Mesh'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      // Fact values stay literal (data, not localized).
      expect(find.text('none'), findsNWidgets(2)); // Session + Events
      expect(find.text('paused'), findsOneWidget);
    });
  });

  group('SummaryCard - error tone', () {
    testWidgets('an error puts the connected state badge on the error plate',
        (tester) async {
      final sum = diagnosticsSummary(
        l: AppLocalizationsEn(),
        session: _readySession(),
        error: 'boom',
      );
      await _pump(tester, SummaryCard(summary: sum));

      // The badge keeps the session's own state; the tone alone signals
      // the error.
      final state = tester.widget<Text>(find.text('Connected'));
      expect(state.style?.color, MoshColors.dark.onErrorContainer);
      final plate = tester.widget<Container>(find
          .ancestor(
              of: find.text('Connected'), matching: find.byType(Container))
          .first);
      expect((plate.decoration! as ShapeDecoration).color,
          MoshColors.dark.errorContainer);
    });
  });
}
