// Widget + pure tests for the Diagnostics-drawer section primitives
// (lib/src/features/diagnostics/diagnostics_sections.dart) and the
// `pathLabel` helper (diagnostics_helpers.dart). Pumps the widgets directly
// inside a localized `MaterialApp` (the established DM widget-test pattern,
// scoped to the section -- no Riverpod/DiagnosticsScreen) and asserts:
//   - `DiagnosticsRow` renders its label + value.
//   - `DiagnosticsGroup` renders its uppercased label + children.
//   - `NoActiveSession` renders the "Session" group label + the empty-state
//     title + description.
//   - `SessionDiagnostics` (Conversation-details group ONLY): for a ready
//     relayed session, the group label + the Peer / MLS-state / Path /
//     Encryption / Role / Display / Session rows render with the right
//     values; for a direct-path session, the Encryption row is absent; for
//     an empty peer display name, the Peer row falls back to "unknown".
//   - `pathLabel` pure tests for every branch (relayed+true/false/null,
//     direct, connecting, empty, weird).
//
// In scope (this atomic): the Conversation-details group + Row +
// NoActiveSession + pathLabel. `MeshDiagnostics`, `EventLog`, and the
// channel/group sections are DEFERRED (no contracts / separate atomics) and
// are not asserted here. `DiagnosticsScreen` wiring is also a later atomic,
// so it is not exercised.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_sections.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// A minimal `SessionSnapshot` builder for the Conversation-details tests.
/// Only the fields the group reads are parameterized; the rest are the
/// frb-required defaults (empty lists, null optionals).
SessionSnapshot _session({
  required String sessionId,
  String peerDisplayName = 'alice',
  String displayName = 'me',
  String state = 'ready',
  String path = 'relayed',
  bool? relayReady = true,
  String role = 'initiator',
}) =>
    SessionSnapshot(
      sessionId: sessionId,
      meshId: 'mesh-1',
      role: role,
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      path: path,
      relayReady: relayReady,
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

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: Center(child: child))),
    ),
  );
  await tester.pumpAndSettle();
}

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
    testWidgets('renders the uppercased label and its children', (tester) async {
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
    testWidgets('ready relayed session renders all 7 rows incl. Encryption',
        (tester) async {
      final s = _session(sessionId: 'sess-1234567890abcdef');
      await _pump(tester, SessionDiagnostics(session: s));

      // Group label (uppercased).
      expect(find.text('CONVERSATION DETAILS'), findsOneWidget);
      // Peer row value is the peer display name.
      expect(find.text('Peer'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      // MLS state row value is the localized ready label ("Connected").
      expect(find.text('MLS state'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      // Path row value is pathLabel("relayed", true).
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('relayed via supernode'), findsOneWidget);
      // Encryption row renders only because path == "relayed".
      expect(find.text('Encryption'), findsOneWidget);
      expect(
        find.text('E2E — supernode sees only ciphertext'),
        findsOneWidget,
      );
      // Role row value is the raw role.
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('initiator'), findsOneWidget);
      // Display row value is the local display name.
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('me'), findsOneWidget);
      // Session row key is "Session" (not uppercased) and the value is
      // shorten(sessionId, 14). The id is 20 chars, which is <= 14*2+1=29,
      // so shorten returns it unchanged.
      expect(find.text('Session'), findsOneWidget);
      expect(find.text('sess-1234567890abcdef'), findsOneWidget);
    });

    testWidgets('direct-path session omits the Encryption row', (tester) async {
      final s = _session(sessionId: 'sess-direct-1234567', path: 'direct');
      await _pump(tester, SessionDiagnostics(session: s));

      // The Path row shows the direct label.
      expect(find.text('Path'), findsOneWidget);
      expect(find.text('direct'), findsOneWidget);
      // The Encryption row key + value are both absent.
      expect(find.text('Encryption'), findsNothing);
      expect(
        find.text('E2E — supernode sees only ciphertext'),
        findsNothing,
      );
    });

    testWidgets('empty peer display name falls back to "unknown"', (tester) async {
      final s = _session(
        sessionId: 'sess-noid1234567890',
        peerDisplayName: '',
      );
      await _pump(tester, SessionDiagnostics(session: s));

      expect(find.text('Peer'), findsOneWidget);
      // The localized "unknown" fallback (en).
      expect(find.text('unknown'), findsOneWidget);
    });

    testWidgets('relayed session with relayReady false shows the warming-up suffix',
        (tester) async {
      final s = _session(
        sessionId: 'sess-warming1234567',
        path: 'relayed',
        relayReady: false,
      );
      await _pump(tester, SessionDiagnostics(session: s));

      expect(find.text('Path'), findsOneWidget);
      expect(
        find.text('relayed via supernode (warming up)'),
        findsOneWidget,
      );
      // Encryption still renders (path is still "relayed").
      expect(find.text('Encryption'), findsOneWidget);
    });
  });

  group('pathLabel', () {
    test('relayed + relayReady true -> "relayed via supernode"', () {
      expect(pathLabel('relayed', true), 'relayed via supernode');
    });

    test('relayed + relayReady false -> warming-up suffix', () {
      expect(
        pathLabel('relayed', false),
        'relayed via supernode (warming up)',
      );
    });

    test('relayed + relayReady null -> "relayed via supernode" (null != false)',
        () {
      expect(pathLabel('relayed', null), 'relayed via supernode');
    });

    test('direct -> "direct"', () {
      expect(pathLabel('direct', null), 'direct');
    });

    test('connecting -> "connecting"', () {
      expect(pathLabel('connecting', null), 'connecting');
    });

    test('empty path -> "unknown"', () {
      expect(pathLabel('', null), 'unknown');
    });

    test('unknown path -> passes through', () {
      expect(pathLabel('weird', null), 'weird');
    });
  });
}
