// The details panel as the Details panel card draws it: the one place a
// conversation shows its encryption, and the way into connection status.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/connection_status_panel.dart';
import 'package:mosh/src/features/conversation/conversation_details_panel.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/panel_head.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/shared/value_row.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/types.dart' show MessageMetadata;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupMessage, GroupNameChanged;
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

const _fingerprint = '0011223344556677';
const _dmHint =
    'The same on both sides. Compare it with your peer over a call or in person.';
const _groupHint =
    'The same for every member. Compare it with the group creator.';

ConversationSnapshot _dm({String fingerprint = _fingerprint}) => DmConversation(
    const DmTarget('dm'),
    TestSnapshots.dm(
        sessionId: 'dm', peerDisplayName: 'Alice', fingerprint: fingerprint));

ConversationSnapshot _group({bool admin = false}) => GroupConversation(
    const GroupTarget('team'),
    TestSnapshots.group(
        groupId: 'team',
        deviceFingerprint: 'me',
        messages: [],
        label: 'Design team',
        isAdmin: admin,
        memberPeerIds: const ['me', 'peer'],
        creatorFingerprint: _fingerprint));

ConversationSnapshot _channel() => ChannelConversation(
    const ChannelTarget('general'),
    TestSnapshots.channel(
        name: 'general', deviceFingerprint: 'me', messages: const []));

Future<void> _pump(WidgetTester tester, AsyncValue<ConversationSnapshot> async,
    {AnyConversationTarget target = const DmTarget('dm'),
    VoidCallback? onClose,
    bool settle = true}) {
  tester.view
    ..physicalSize = const Size(360, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpScreen(
      tester,
      Scaffold(
          body: ConversationDetailsPanel(
              target: target,
              async: async,
              onClose: onClose ?? () {},
              onOpenAttachment: (_, __, ___) {})),
      overrides: [gatewayProvider.overrideWithValue(ScriptableGateway())],
      settle: settle);
}

void main() {
  testWidgets('the encryption row opens the fingerprint to compare',
      (tester) async {
    await _pump(tester, AsyncData(_dm()));
    expect(find.text('Compare the fingerprint to verify'), findsOneWidget);

    await tester.tap(find.text('End-to-end encrypted'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsOneWidget);
    expect(find.text(_fingerprint), findsOneWidget);
    expect(find.text(fingerprintEmoji(_fingerprint).join(' ')), findsOneWidget);
    expect(find.text(_dmHint), findsOneWidget);

    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Encryption fingerprint'), findsNothing);
  });

  testWidgets('a group compares its fingerprint with the group creator',
      (tester) async {
    final snapshot = _group();
    await _pump(tester, AsyncData(snapshot), target: snapshot.target);
    await tester.tap(find.text('End-to-end encrypted'));
    await tester.pumpAndSettle();
    expect(find.text(_fingerprint), findsOneWidget);
    expect(find.text(_groupHint), findsOneWidget);
    expect(find.text(_dmHint), findsNothing);
  });

  testWidgets('a conversation whose fingerprint is not known has no row',
      (tester) async {
    await _pump(tester, AsyncData(_dm(fingerprint: '')));
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('End-to-end encrypted'), findsNothing);
  });

  testWidgets('a public channel says it is not encrypted and has no row',
      (tester) async {
    final snapshot = _channel();
    await _pump(tester, AsyncData(snapshot), target: snapshot.target);
    expect(find.text('Public channel, not encrypted'), findsOneWidget);
    expect(find.text('End-to-end encrypted'), findsNothing);
  });

  testWidgets('the user\'s own row among the participants says it is theirs',
      (tester) async {
    await _pump(tester, AsyncData(_dm()));
    expect(find.textContaining('(you)'), findsOneWidget);
    expect(find.text('Alice (you)'), findsNothing);
  });

  testWidgets('only the admin of a group carries the admin mark',
      (tester) async {
    for (final admin in [true, false]) {
      final snapshot = _group(admin: admin);
      await _pump(tester, AsyncData(snapshot), target: snapshot.target);
      expect(find.byTooltip('Admin'), admin ? findsOneWidget : findsNothing);
    }
  });

  // A rename notice reaches the panel as the runtime hands it over: with no
  // signed origin, and under the name the device had when it was sent. Only
  // an org group comes with a roster.
  for (final org in [true, false]) {
    testWidgets(
        'an unsigned rename notice leaves the admin\'s own row theirs in '
        '${org ? 'an org group with its roster' : 'a plain group without one'}',
        (tester) async {
      final snapshot = GroupConversation(
          const GroupTarget('team'),
          TestSnapshots.group(
              groupId: 'team',
              deviceFingerprint: 'me',
              displayName: 'Alex',
              label: 'Crew',
              orgPubkey: org ? 'org-key' : null,
              memberPeerIds: org ? const ['peer', 'me'] : const [],
              messages: const [
                GroupMessage(
                    metadata: MessageMetadata(
                        canDeleteForEveryone: false, localOnly: true),
                    fromDevice: 'Old laptop',
                    fromFingerprint: 'me',
                    body: '',
                    nameChange: GroupNameChanged(name: 'Crew')),
              ]));
      await _pump(tester, AsyncData(snapshot), target: snapshot.target);
      expect(find.text('Alex (you)'), findsOneWidget);
      expect(find.textContaining('Old laptop'), findsNothing);
      expect(find.byTooltip('Admin'), findsOneWidget);
    });
  }

  testWidgets(
      'connection details show the readings and lead to connection status, '
      'which closes back to the details', (tester) async {
    var closed = 0;
    await _pump(tester, AsyncData(_dm()), onClose: () => closed++);
    expect(find.byType(ValueRow), findsNothing);

    await tester.tap(find.text('Connection details'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ValueRow>(find.byType(ValueRow).first),
        isA<ValueRow>()
            .having((row) => row.label, 'label', 'Status')
            .having((row) => row.value, 'value', 'Connected'));

    await tester.ensureVisible(find.text('Open connection status'));
    await tester.tap(find.text('Open connection status'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionStatusPanel), findsOneWidget);
    expect(find.widgetWithText(PanelHead, 'Connection status'), findsOneWidget);

    await tester.tap(find.byTooltip('Close connection status'));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(PanelHead, 'Conversation details'), findsOneWidget);
    expect(closed, 0);
  });

  testWidgets('while the conversation loads the panel shows its head',
      (tester) async {
    // The spinner never settles.
    await _pump(tester, const AsyncLoading(), settle: false);
    expect(find.text('Conversation details'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the panel reused for another chat opens on its details',
      (tester) async {
    await _pump(tester, AsyncData(_dm()));
    await tester.tap(find.text('Connection details'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open connection status'));
    await tester.tap(find.text('Open connection status'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionStatusPanel), findsOneWidget);

    final group = _group();
    await _pump(tester, AsyncData(group), target: group.target);
    expect(find.byType(ConnectionStatusPanel), findsNothing);
    expect(
        find.widgetWithText(PanelHead, 'Conversation details'), findsOneWidget);
  });

  testWidgets('a long label in large text leaves the value its place',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(
        tester,
        const Scaffold(
            body: SizedBox(
                width: 280,
                child: ValueRow(
                    label: 'Последнее подключение к собеседнику',
                    value: 'requested, moss is dialing'))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('requested, moss is dialing')).width,
        greaterThan(100));
  });
}
