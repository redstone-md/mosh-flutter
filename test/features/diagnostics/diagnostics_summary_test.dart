// Pure-logic tests for `diagnosticsSummary` + the `peerCount`/`natType`/
// `relayStatus` helpers (lib/src/features/diagnostics/diagnostics_summary.dart
// + diagnostics_helpers.dart). The summary builder is pure given an
// `AppLocalizations`, so the tests construct the real `AppLocalizationsEn`
// (the en delegate) and assert on the returned `DiagnosticSummary` fields
// for the DM and idle/error branches.
//
// In scope (this atomic): the DM branch (ready/waiting/unknown-state +
// error override) and the idle/error (no-active-session) branch. The
// channel + group branches are DEFERRED (no contracts in the Flutter
// fork yet) -- they are not asserted here.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations_en.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/diagnostics_summary.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';

AppLocalizationsEn _l = AppLocalizationsEn();

MeshInfo _mesh({
  int peerCount = 0,
  int relaySessionCount = 0,
  int relayedPeerCount = 0,
  int relayCapablePeerCount = 0,
  String natType = 'unknown',
}) =>
    MeshInfo(
      meshId: 'mesh-1',
      listenPort: 0,
      advertisedAddr: '',
      peerCount: peerCount,
      directPeerCount: 0,
      relayedPeerCount: relayedPeerCount,
      relayCapablePeerCount: relayCapablePeerCount,
      relaySessionCount: relaySessionCount,
      relayRouteCount: 0,
      knownPeerCount: 0,
      channels: const [],
      natType: natType,
      supernodeReady: false,
      publicKey: '',
      peerDetails: const [],
    );

SessionSnapshot _session({
  required DmSessionState state,
  String displayName = 'me',
  String peerDisplayName = 'Alice',
  MeshInfo? mesh,
}) =>
    SessionSnapshot(
      sessionId: 'sess-1',
      meshId: 'mesh-1',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: mesh,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

DiagnosticSummaryFact _fact(String label, String value) =>
    DiagnosticSummaryFact(label: label, value: value);

void main() {
  group('diagnosticsSummary - DM branch', () {
    test('ready session with peers -> tone ready, ready-with-peers description',
        () {
      final s =
          _session(state: DmSessionState.connected, mesh: _mesh(peerCount: 1));
      final sum = diagnosticsSummary(l: _l, session: s);

      expect(sum.tone, DiagnosticSummaryTone.ready);
      expect(sum.kicker, 'Private DM');
      expect(sum.title, 'Alice'); // peerDisplayName wins
      expect(sum.state, 'Connected'); // stateReady
      expect(sum.description,
          'MLS is ready and Moss sees at least one peer on this mesh.');
      expect(sum.facts, [
        _fact('Peers', '1'),
        _fact('NAT', 'unknown'),
        _fact('Relay', 'none'),
      ]);
    });

    test('ready session with zero peers -> ready-no-peers description', () {
      final s =
          _session(state: DmSessionState.connected, mesh: _mesh(peerCount: 0));
      final sum = diagnosticsSummary(l: _l, session: s);

      expect(sum.tone, DiagnosticSummaryTone.ready);
      expect(sum.description,
          'MLS is ready; Moss peer telemetry is still catching up.');
    });

    test(
        'ready session with null mesh -> ready-no-peers description, booting facts',
        () {
      final s = _session(state: DmSessionState.connected, mesh: null);
      final sum = diagnosticsSummary(l: _l, session: s);

      expect(sum.tone, DiagnosticSummaryTone.ready);
      expect(sum.description,
          'MLS is ready; Moss peer telemetry is still catching up.');
      expect(sum.facts, [
        _fact('Peers', 'booting'),
        _fact('NAT', 'unknown'),
        _fact('Relay', 'booting'),
      ]);
    });

    test('pending session -> tone waiting, waiting-for-contact copy', () {
      final s =
          _session(state: DmSessionState.pending, mesh: _mesh(peerCount: 1));
      final sum = diagnosticsSummary(l: _l, session: s);

      expect(sum.tone, DiagnosticSummaryTone.waiting);
      expect(sum.state, 'Waiting for your contact');
      expect(sum.description,
          'Invite created. Waiting for the peer and Moss mesh to complete discovery.');
    });

    test('handshaking session -> tone waiting, contact-is-offline copy', () {
      final s = _session(state: DmSessionState.handshaking, mesh: null);
      final sum = diagnosticsSummary(l: _l, session: s);

      expect(sum.tone, DiagnosticSummaryTone.waiting);
      expect(sum.state, 'Contact is offline');
      expect(
          sum.description,
          'Contact is offline. Messages will be delivered when you are both '
          'online');
    });

    test('DM session with error -> tone error overrides state-based tone', () {
      final s =
          _session(state: DmSessionState.connected, mesh: _mesh(peerCount: 1));
      final sum = diagnosticsSummary(l: _l, session: s, error: 'boom');

      // Tone is error even though state is ready.
      expect(sum.tone, DiagnosticSummaryTone.error);
      // The state badge still reflects the localized state (ready -> Connected).
      expect(sum.state, 'Connected');
      // The description still reflects the session state (ready-with-peers).
      expect(sum.description,
          'MLS is ready and Moss sees at least one peer on this mesh.');
    });

    test(
        'title fallback: empty peerDisplayName -> displayName -> Private session',
        () {
      expect(
        diagnosticsSummary(
            l: _l,
            session: _session(
              state: DmSessionState.connected,
              displayName: 'bob',
              peerDisplayName: '',
            )).title,
        'bob',
      );
      expect(
        diagnosticsSummary(
            l: _l,
            session: _session(
              state: DmSessionState.connected,
              displayName: '',
              peerDisplayName: '',
            )).title,
        'Private session',
      );
    });
  });

  group('diagnosticsSummary - idle/error branch', () {
    test('no session, no error -> tone idle, idle copy, Waiting state', () {
      final sum = diagnosticsSummary(l: _l, session: null);

      expect(sum.tone, DiagnosticSummaryTone.idle);
      expect(sum.kicker, 'Diagnostics idle');
      expect(sum.title, 'No active session');
      expect(sum.state, 'Waiting');
      expect(sum.description,
          'Open a conversation to inspect connection state, peer count, NAT, relay, and events.');
      expect(sum.facts, [
        _fact('Session', 'none'),
        _fact('Mesh', 'paused'),
        _fact('Events', 'none'),
      ]);
    });

    test('no session WITH error -> tone error, Error state', () {
      final sum = diagnosticsSummary(l: _l, session: null, error: 'boom');

      expect(sum.tone, DiagnosticSummaryTone.error);
      expect(sum.state, 'Error');
      // Kicker/title/description/facts still come from the idle branch.
      expect(sum.kicker, 'Diagnostics idle');
      expect(sum.title, 'No active session');
      expect(sum.facts, [
        _fact('Session', 'none'),
        _fact('Mesh', 'paused'),
        _fact('Events', 'none'),
      ]);
    });
  });

  group('helpers', () {
    test('peerCount: null mesh -> "booting"', () {
      expect(peerCount(null), 'booting');
    });

    test('peerCount: mesh with peerCount=5 -> "5"', () {
      expect(peerCount(_mesh(peerCount: 5)), '5');
    });

    test('natType: null mesh -> "unknown"', () {
      expect(natType(null), 'unknown');
    });

    test('natType: empty-string natType -> "unknown" (JS || falsy fallback)',
        () {
      expect(natType(_mesh(natType: '')), 'unknown');
    });

    test('natType: populated natType -> passes through', () {
      expect(natType(_mesh(natType: 'full-cone')), 'full-cone');
    });

    test('relayStatus: relaySessionCount > 0 -> "{n} active"', () {
      expect(relayStatus(_mesh(relaySessionCount: 2)), '2 active');
    });

    test('relayStatus: relayedPeerCount > 0 (no sessions) -> "{n} relayed"',
        () {
      expect(
        relayStatus(_mesh(
          relaySessionCount: 0,
          relayedPeerCount: 3,
        )),
        '3 relayed',
      );
    });

    test(
        'relayStatus: relayCapablePeerCount > 0 (no sessions/relayed) -> "{n} capable"',
        () {
      expect(
        relayStatus(_mesh(
          relaySessionCount: 0,
          relayedPeerCount: 0,
          relayCapablePeerCount: 1,
        )),
        '1 capable',
      );
    });

    test('relayStatus: all zero -> "none"', () {
      expect(relayStatus(_mesh()), 'none');
    });
  });

  group('DiagnosticSummary value semantics', () {
    test('equality + hashCode on equal summaries', () {
      final a = diagnosticsSummary(
          l: _l,
          session: _session(
            state: DmSessionState.connected,
            mesh: _mesh(peerCount: 1),
          ));
      final b = diagnosticsSummary(
          l: _l,
          session: _session(
            state: DmSessionState.connected,
            mesh: _mesh(peerCount: 1),
          ));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equality differs when facts differ', () {
      final a = diagnosticsSummary(
          l: _l,
          session: _session(
            state: DmSessionState.connected,
            mesh: _mesh(peerCount: 1),
          ));
      final b = diagnosticsSummary(
          l: _l,
          session: _session(
            state: DmSessionState.connected,
            mesh: _mesh(peerCount: 2),
          ));
      expect(a == b, isFalse);
    });
  });
}
