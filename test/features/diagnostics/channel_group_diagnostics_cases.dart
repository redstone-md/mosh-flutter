import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/diagnostics/channel_group_diagnostics.dart';
import 'package:mosh/src/rust/api/diagnostics.dart' show MossLibraryInfo;
import 'package:mosh/src/rust/conversation/mesh.dart' show SnapshotEvent;

import '../../support/message_builders.dart';
import '../../support/pump.dart';

const _device = '0123456789abcdefghijklmnopTAIL';
final _library = MossLibraryInfo(
  version: 'moss-test-1.2.3',
  peerRttMs: BigInt.from(42),
  logPath: '/tmp/mosh-field.log',
);

List<SnapshotEvent> _events(String name) => [
      SnapshotEvent(
        eventType: 1,
        eventName: name,
        detailJson: '',
        epochMillis: BigInt.from(1700000000000),
      ),
    ];

Future<void> _pump(WidgetTester tester, Widget child) => pumpScreen(
      tester,
      Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('channel shows its native details, network and events',
      (tester) async {
    final channel = TestSnapshots.channel(
      name: 'mosh-dev',
      displayName: 'Alice workstation',
      topic: 'Development discussion',
      deviceFingerprint: _device,
      messages: const [],
      mesh: TestSnapshots.mesh(meshId: 'channel-mesh'),
      events: _events('channelJoined'),
    );
    await _pump(
      tester,
      ChannelDiagnostics(channel: channel, libraryInfo: _library),
    );

    for (final text in [
      'CHANNEL DETAILS',
      '#mosh-dev',
      'Alice workstation',
      'Development discussion',
      '0123456789…TAIL',
      'MOSS NETWORK',
      'channel-mesh',
      'moss-test-1.2.3',
      '/tmp/mosh-field.log',
      'MOSS EVENTS',
      'channelJoined',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Peer RTT'), findsNothing);
    expect(find.text('No events yet'), findsNothing);
  });

  testWidgets('connected group shows its admin role and runtime evidence',
      (tester) async {
    final group = TestSnapshots.group(
      groupId: 'group-abcdefghijklmnopqrstuvwxyz0123456789',
      label: 'Research team',
      displayName: 'Bob laptop',
      creatorFingerprint: 'creator-abcdefghijklmnopqrstuvwxyz0123456789',
      deviceFingerprint: _device,
      memberCount: BigInt.from(3),
      messages: const [],
      mesh: TestSnapshots.mesh(meshId: 'group-mesh'),
      events: _events('groupMemberAdded'),
    );
    await _pump(tester, GroupDiagnostics(group: group, libraryInfo: _library));

    for (final text in [
      'GROUP DETAILS',
      'Research team',
      '3',
      'admin',
      'Connected',
      'Bob laptop',
      'group-abcdef…6789',
      'creator-…6789',
      '0123456789…TAIL',
      'group-mesh',
      'moss-test-1.2.3',
      'groupMemberAdded',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Peer RTT'), findsNothing);
  });

  testWidgets('joining member has no invented label, connection or events',
      (tester) async {
    final group = TestSnapshots.group(
      groupId: 'joining-group',
      deviceFingerprint: 'member-device',
      messages: const [],
      isAdmin: false,
      state: 'connecting',
    );
    await _pump(tester, GroupDiagnostics(group: group));

    for (final text in [
      '-',
      'member',
      'Waiting',
      'Mesh booting',
      'No events yet'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Connected'), findsNothing);
    expect(find.text('admin'), findsNothing);
  });
}
