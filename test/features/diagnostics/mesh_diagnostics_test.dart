// Widget + pure tests for `MeshDiagnostics` + `Metric`
// (lib/src/features/diagnostics/mesh_diagnostics.dart) and the
// `peerBreakdown` / `relayBreakdown` helpers
// (diagnostics_helpers.dart). Pumps the widgets directly inside a
// localized `MaterialApp` (the established DM widget-test pattern,
// scoped to the section -- no Riverpod/DiagnosticsScreen) and asserts:
//   - `peerBreakdown` / `relayBreakdown` pure: the exact "n direct /
//     n relayed" and "n capable / n routes" strings.
//   - `MeshDiagnostics` with `mesh == null` -> the "Moss network" group
//     label + the "Mesh booting" empty-state title + description.
//   - `MeshDiagnostics` with a full mesh -> the "Moss network" group
//     label, the 4 Metric cells (Peers value = peerCount, NAT value =
//     natType, Relay value = relayStatus, Supernode value ready/standby
//     by `supernodeReady`), and the 7 rows (Advertised, Listen port,
//     Known peers, Relay routes, Channels, Mesh id, Public key).
//   - empty `advertisedAddr` -> Advertised row value "-".
//   - empty `channels` -> Channels row value "-".
//
// `EventLog` is DEFERRED (separate atomic) and is not asserted here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/diagnostics/diagnostics_helpers.dart';
import 'package:mosh/src/features/diagnostics/mesh_diagnostics.dart';
import 'package:mosh/src/rust/conversation/mesh.dart';
import '../../support/pump.dart';

/// A full `MeshInfo` builder for the widget tests. Only the fields the
/// group reads are parameterized; the rest are sensible defaults.
MeshInfo _mesh({
  String meshId = 'mesh-0123456789abcdef',
  int listenPort = 4242,
  String advertisedAddr = '203.0.113.7:4242',
  int peerCount = 5,
  int directPeerCount = 2,
  int relayedPeerCount = 3,
  int relayCapablePeerCount = 1,
  int relaySessionCount = 0,
  int relayRouteCount = 4,
  int knownPeerCount = 9,
  List<String> channels = const ['mosh-dev', 'mosh-ops'],
  String natType = 'full-cone',
  bool supernodeReady = true,
  String publicKey = 'pk-0123456789abcdef',
}) =>
    MeshInfo(
      meshId: meshId,
      listenPort: listenPort,
      advertisedAddr: advertisedAddr,
      peerCount: peerCount,
      directPeerCount: directPeerCount,
      relayedPeerCount: relayedPeerCount,
      relayCapablePeerCount: relayCapablePeerCount,
      relaySessionCount: relaySessionCount,
      relayRouteCount: relayRouteCount,
      knownPeerCount: knownPeerCount,
      channels: channels,
      natType: natType,
      supernodeReady: supernodeReady,
      publicKey: publicKey,
      peerDetails: const [],
    );

Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(child: Center(child: child)),
    ));

void main() {
  group('peerBreakdown', () {
    test('2 direct / 3 relayed', () {
      final m = _mesh(directPeerCount: 2, relayedPeerCount: 3);
      expect(peerBreakdown(m), '2 direct / 3 relayed');
    });
  });

  group('relayBreakdown', () {
    test('1 capable / 4 routes', () {
      final m = _mesh(relayCapablePeerCount: 1, relayRouteCount: 4);
      expect(relayBreakdown(m), '1 capable / 4 routes');
    });
  });

  group('MeshDiagnostics - booting', () {
    testWidgets(
        'null mesh renders the Moss network group + booting empty-state',
        (tester) async {
      await _pump(tester, const MeshDiagnostics(mesh: null));

      // Group label "Moss network" is uppercased in the widget.
      expect(find.text('MOSS NETWORK'), findsOneWidget);
      // The booting empty-state title + description.
      expect(find.text('Mesh booting'), findsOneWidget);
      expect(
        find.text(
          'Network facts appear after Moss binds a port and receives its '
          'first runtime poll.',
        ),
        findsOneWidget,
      );
    });
  });

  group('MeshDiagnostics - full mesh', () {
    testWidgets('renders the group label, the 4 metrics, and the 7 rows',
        (tester) async {
      final m = _mesh();
      await _pump(tester, MeshDiagnostics(mesh: m));

      // Group label.
      expect(find.text('MOSS NETWORK'), findsOneWidget);

      // Metric labels (Peers/NAT/Relay reuse the summary fact labels,
      // Supernode is its own key).
      expect(find.text('Peers'), findsOneWidget);
      expect(find.text('NAT'), findsOneWidget);
      expect(find.text('Relay'), findsOneWidget);
      expect(find.text('Supernode'), findsOneWidget);

      // Metric VALUES (data, literal):
      //   Peers = peerCount(mesh) = "5"
      //   NAT = natType(mesh) = "full-cone"
      //   Relay = relayStatus(mesh): relaySessionCount=0, relayedPeerCount=3
      //           -> "3 relayed"
      //   Supernode = supernodeReady ? "ready" : "standby" -> "ready"
      expect(find.text('5'), findsOneWidget);
      expect(find.text('full-cone'), findsOneWidget);
      expect(find.text('3 relayed'), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);
      // Metric details (status tokens, literal).
      expect(find.text('2 direct / 3 relayed'), findsOneWidget);
      expect(find.text('reported type'), findsOneWidget);
      expect(find.text('1 capable / 4 routes'), findsOneWidget);
      expect(find.text('can assist peers'), findsOneWidget);

      // The 7 rows. Advertised = advertisedAddr, Listen port = port,
      // Known peers = knownPeerCount, Relay routes = relayRouteCount,
      // Channels = channels.length, Mesh id = shorten(meshId, 14),
      // Public key = shorten(publicKey, 12).
      expect(find.text('Advertised'), findsOneWidget);
      expect(find.text('203.0.113.7:4242'), findsOneWidget);
      expect(find.text('Listen port'), findsOneWidget);
      expect(find.text('4242'), findsOneWidget);
      expect(find.text('Known peers'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Relay routes'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Mesh id'), findsOneWidget);
      // shorten(meshId, 14): id is 20 chars > 14*2+1=29? 20 <= 29 -> unchanged.
      expect(find.text('mesh-0123456789abcdef'), findsOneWidget);
      expect(find.text('Public key'), findsOneWidget);
      // shorten(publicKey, 12): "pk-0123456789abcdef" is 19 chars > 12*2+1=25?
      // 19 <= 25 -> unchanged.
      expect(find.text('pk-0123456789abcdef'), findsOneWidget);
    });

    testWidgets('supernodeReady false -> "standby" + "not promoted"',
        (tester) async {
      final m = _mesh(supernodeReady: false);
      await _pump(tester, MeshDiagnostics(mesh: m));

      expect(find.text('Supernode'), findsOneWidget);
      expect(find.text('standby'), findsOneWidget);
      expect(find.text('not promoted'), findsOneWidget);
    });

    testWidgets('empty advertisedAddr -> Advertised row value "-"',
        (tester) async {
      final m = _mesh(advertisedAddr: '');
      await _pump(tester, MeshDiagnostics(mesh: m));

      expect(find.text('Advertised'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('empty channels -> Channels row value "-"', (tester) async {
      final m = _mesh(channels: const []);
      await _pump(tester, MeshDiagnostics(mesh: m));

      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });
  });
}
