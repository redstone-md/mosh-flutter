// Widget tests for the Diagnostics-drawer section primitives
// (lib/src/features/diagnostics/diagnostics_sections.dart). Pumps the
// widgets directly inside a localized `MaterialApp` (the established DM
// widget-test pattern, scoped to the section -- no Riverpod /
// DiagnosticsScreen) and asserts:
//   - `DiagnosticsRow` renders its label + value.
//   - `DiagnosticsGroup` renders its uppercased label + children.
//   - `NoActiveSession` renders the "Session" group label + the empty-state
//     title + description.
//   - `SessionDiagnostics` (Conversation-details group ONLY): the Peer /
//     MLS state / Transport / Peer id / Last connect / Role / Display /
//     Session rows for each of the three states and three transports; a
//     session whose peer id is not known yet says so next to its state, so
//     "Connected" and "peer unknown" never share a card; no row mentions a
//     relay the app runs itself.
//
// `MeshDiagnostics`, `EventLog`, and the channel/group sections are covered
// by their own tests and are not asserted here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import '../../support/pump.dart';

const String _peerId =
    'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';

/// A minimal `SessionSnapshot` builder for the Conversation-details tests.
/// Only the fields the group reads are parameterized; the rest are the
/// frb-required defaults (empty lists, null optionals).
SessionSnapshot _session({
  String sessionId = 'sess-1234567890abcdef',
  String peerDisplayName = 'alice',
  String displayName = 'me',
  DmSessionState state = DmSessionState.connected,
  PeerTransport transport = PeerTransport.direct,
  String? peerMossId = _peerId,
  ConnectOutcome? lastConnectOutcome = ConnectOutcome.requested,
  String role = 'initiator',
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'mesh-1',
      role: role,
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      transport: transport,
      peerMossId: peerMossId,
      lastConnectOutcome: lastConnectOutcome,
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

Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
    tester, Scaffold(body: SingleChildScrollView(child: Center(child: child))));

void main() {
  group('DiagnosticsRow', () {
    testWidgets('renders its label and value', (tester) async {
      await _pump(
        tester,
        const DiagnosticsRow(label: 'Peer', value: 'alice'),
      );
      expect(find.text('Peer'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });
  });

  group('DiagnosticsGroup', () {
    testWidgets('renders the uppercased label and its children',
        (tester) async {
      await _pump(
        tester,
        DiagnosticsGroup(
          label: 'Conversation details',
          children: const [
            DiagnosticsRow(label: 'Peer', value: 'alice'),
          ],
        ),
      );
      // The group label is uppercased in the widget.
      expect(find.text('CONVERSATION DETAILS'), findsOneWidget);
      // The child row renders inside the group.
      expect(find.text('Peer'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });
  });

  group('NoActiveSession', () {
    testWidgets('renders the Session group label + empty-state title + body',
        (tester) async {
      await _pump(tester, const NoActiveSession());
      // The group label "Session" is uppercased.
      expect(find.text('SESSION'), findsOneWidget);
      // The empty-state title + description.
      expect(find.text('No active session'), findsOneWidget);
      expect(
        find.text(
          'Select a DM, channel, or group to inspect its Moss network '
          'and recent events.',
        ),
        findsOneWidget,
      );
    });
  });

  group('SessionDiagnostics - Conversation details', () {
    testWidgets('a connected direct session renders all 8 rows',
        (tester) async {
      await _pump(tester, SessionDiagnostics(session: _session()));

      expect(find.text('CONVERSATION DETAILS'), findsOneWidget);
      expect(find.text('Peer'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('MLS state'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('direct'), findsOneWidget);
      // The peer id is shortened to its ends.
      expect(find.text('Peer id'), findsOneWidget);
      expect(find.text('cdcdcdcd…cdcd'), findsOneWidget);
      expect(find.text('Last connect'), findsOneWidget);
      expect(find.text('requested, moss is dialing'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('initiator'), findsOneWidget);
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('me'), findsOneWidget);
      // The id is 20 chars, which is <= 14*2+1=29, so shorten keeps it.
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('sess-1234567890abcdef'), findsOneWidget);
    });

    testWidgets('a relayed session says the network relays it', (tester) async {
      await _pump(
        tester,
        SessionDiagnostics(session: _session(transport: PeerTransport.relayed)),
      );
      expect(find.text('relayed by the network'), findsOneWidget);
      // Nothing about a relay node of the app's own.
      expect(find.textContaining('supernode'), findsNothing);
      expect(find.text('Encryption'), findsNothing);
    });

    testWidgets('a pending session has no path and no peer id yet',
        (tester) async {
      await _pump(
        tester,
        SessionDiagnostics(
          session: _session(
            state: DmSessionState.pending,
            transport: PeerTransport.none,
            peerMossId: null,
            lastConnectOutcome: null,
            peerDisplayName: '',
          ),
        ),
      );
      expect(find.text('Waiting for your contact'), findsOneWidget);
      expect(find.text('no path yet'), findsOneWidget);
      expect(find.text('not yet known'), findsOneWidget);
      expect(find.text('not requested yet'), findsOneWidget);
      // The localized "unknown" fallback for the display name.
      expect(find.text('unknown'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('an offline contact reads as offline with its last outcome',
        (tester) async {
      await _pump(
        tester,
        SessionDiagnostics(
          session: _session(
            state: DmSessionState.handshaking,
            transport: PeerTransport.none,
            lastConnectOutcome: ConnectOutcome.failed,
          ),
        ),
      );
      expect(find.text('Contact is offline'), findsOneWidget);
      expect(find.text('no path yet'), findsOneWidget);
      expect(find.text('moss refused the request, retrying'), findsOneWidget);
    });
  });
}
