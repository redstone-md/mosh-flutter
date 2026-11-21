// Diagnostics: the desktop "Connection status" drawer over a DM, channel and
// group, and the phone's details panel with "Connection details" expanded.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/diagnostics/event_log.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/conversation/mesh.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_dm_runtime/transport.dart';

import '../../../test/support/message_builders.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'harness.dart';
import 'settings_support.dart';

const _desktop = [FigmaDevice.desktop];
const _peerId =
    '7f3a9c21d84e5b06a1c2e3f405162738495a6b7c8d9e0f1a2b3c4d5e6f708192';
final _now = DateTime(2026, 10, 3, 9, 41);

MeshInfo _mesh({List<String> channels = const []}) => MeshInfo(
      meshId: 'mesh-4f2a91c07b3e',
      listenPort: 41641,
      advertisedAddr: '198.51.100.23:41641',
      peerCount: 6,
      directPeerCount: 4,
      relayedPeerCount: 2,
      relayCapablePeerCount: 3,
      relaySessionCount: 1,
      relayRouteCount: 2,
      knownPeerCount: 14,
      channels: channels,
      natType: 'port-restricted',
      supernodeReady: true,
      publicKey: 'b3f1c9a27d4e8f60a1b2c3d4e5f60718',
      peerDetails: const [],
    );

List<SnapshotEvent> _events() => [
      for (final (i, (name, detail)) in const [
        ('tracker_update', '{"trackers":3,"peers":14}'),
        ('peer_joined', '{"peer":"7f3a9c21"}'),
        ('handshake_complete', '{"peer":"7f3a9c21","transport":"direct"}'),
        ('relay_changed', '{"from":"none","to":"eu-west-2"}'),
        ('message_delivered', '{"id":"m-2041"}'),
        ('peer_rtt', '{"peer":"7f3a9c21","ms":42}'),
      ].indexed)
        SnapshotEvent(
            eventType: i,
            eventName: name,
            detailJson: detail,
            epochMillis: BigInt.from(
                _now.add(Duration(seconds: 17 * i)).millisecondsSinceEpoch)),
    ];

SessionSnapshot _dm({
  DmSessionState state = DmSessionState.connected,
  PeerTransport transport = PeerTransport.direct,
  bool populated = true,
}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: 'maya',
      meshId: 'mesh-4f2a91c07b3e',
      role: 'inviter',
      displayName: 'Alex Rivera',
      peerDisplayName: 'Maya Chen',
      state: state,
      transport: transport,
      peerMossId: populated ? _peerId : null,
      lastConnectOutcome:
          populated ? ConnectOutcome.requested : ConnectOutcome.failed,
      inviteUri: null,
      fingerprint: '9c41e07a5b3d2f18',
      messages: [
        TestMessages.dm(
            fromDevice: 'Maya Chen',
            body: 'See you by the bridge!',
            messageId: 'm1',
            sentAtMs: BigInt.from(_now.millisecondsSinceEpoch)),
      ],
      attachments: const [],
      mesh: populated ? _mesh() : null,
      events: populated ? _events() : const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );

ScriptableGateway _gateway({SessionSnapshot? dm}) => ScriptableGateway()
  ..seedSessions([dm ?? _dm()])
  ..seedChannels([
    TestSnapshots.channel(
        name: 'design-crit',
        topic: 'Weekly design critique',
        deviceFingerprint: '9c41e07a5b3d2f18',
        displayName: 'Alex Rivera',
        mesh: _mesh(channels: const ['design-crit']),
        events: _events().take(3).toList(),
        messages: [
          TestMessages.channel(
              fromDevice: 'Leo Park',
              fromFingerprint: 'a17c',
              body: 'New mockups are up.'),
        ]),
  ])
  ..seedGroups([
    TestSnapshots.group(
        groupId: 'trail-crew',
        label: 'Trail crew',
        deviceFingerprint: '9c41e07a5b3d2f18',
        memberCount: BigInt.from(5),
        mesh: _mesh(),
        events: _events().take(4).toList(),
        messages: [
          TestMessages.group(
              fromDevice: 'Priya Nair',
              fromFingerprint: 'b28d',
              body: 'Saturday 8am at the trailhead?'),
        ]),
  ]);

/// Opens [location] and its "Connection status" drawer from the title bar.
Future<void> _drawer(WidgetTester tester, Size size, String location,
    {ScriptableGateway? gateway}) async {
  final g = gateway ?? _gateway();
  final bridge = settingsBridge(g)
    ..seedMossLibraryInfo(MossLibraryInfo(
        version: '0.9.3', peerRttMs: BigInt.from(42), logPath: null));
  await mountSettings(tester, size,
      location: location, gateway: g, bridge: bridge);
  await tester.tap(find.byTooltip(l10n.peerStatusTitle).first);
  await tester.pumpAndSettle();
}

final diagnosticsScenes = [
  FigmaScene('diag-dm', 'Diagnostics / Connection status / DM connected',
      (tester, size) async {
    await _drawer(tester, size, AppRoutes.dmFor('maya'));
  }, devices: _desktop),
  FigmaScene('diag-dm-events',
      'Diagnostics / Connection status / DM mesh and event log',
      (tester, size) async {
    await _drawer(tester, size, AppRoutes.dmFor('maya'));
    await revealTop(tester, find.byType(EventLog));
  }, devices: _desktop),
  FigmaScene('diag-dm-waiting',
      'Diagnostics / Connection status / DM waiting, mesh booting',
      (tester, size) async {
    await _drawer(tester, size, AppRoutes.dmFor('maya'),
        gateway: _gateway(
            dm: _dm(
                state: DmSessionState.handshaking,
                transport: PeerTransport.relayed,
                populated: false)));
  }, devices: _desktop),
  FigmaScene('diag-error', 'Diagnostics / Connection status / Runtime error',
      (tester, size) async {
    final g = _gateway();
    await _drawer(tester, size, AppRoutes.dmFor('maya'), gateway: g);
    g.failAlways(GatewayMethod.poll,
        error: const ConversationBridgeError(
            kind: ConversationBridgeErrorKind.unavailable,
            message: 'moss runtime unavailable'));
    await tester.tap(find.byTooltip(l10n.refreshStatus));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }, devices: _desktop),
  FigmaScene('diag-channel', 'Diagnostics / Connection status / Channel',
      (tester, size) async {
    await _drawer(tester, size, AppRoutes.channelFor('design-crit'));
  }, devices: _desktop),
  FigmaScene('diag-group', 'Diagnostics / Connection status / Group',
      (tester, size) async {
    await _drawer(tester, size, AppRoutes.groupFor('trail-crew'));
  }, devices: _desktop),
  FigmaScene(
      'diag-details', 'Diagnostics / Conversation details / Connection details',
      (tester, size) async {
    final g = _gateway();
    await mountSettings(tester, size,
        location: AppRoutes.dmFor('maya'), gateway: g);
    await tester.tap(find.byType(ConversationHeaderTitle).first);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text(l10n.chatDetailsDiagnostics));
    await revealTop(tester, find.text(l10n.chatDetailsDiagnostics));
  }),
];
