// The details panel as the Details panel card draws it: the one place a
// conversation shows its encryption, and the way into connection status.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/connection_status_panel.dart';
import 'package:mosh/src/features/conversation/conversation_details_panel.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/panel_head.dart';
import 'package:mosh/src/features/fingerprint/fingerprint_emoji.dart';
import 'package:mosh/src/features/shared/value_row.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
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
    expect(find.text(fingerprintEmoji(_fingerprint).join()), findsOneWidget);
    expect(find.text(_dmHint), findsOneWidget);

    await tester.tap(find.text('Close'));
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

  testWidgets('only the admin of a group carries the admin mark',
      (tester) async {
    for (final admin in [true, false]) {
      final snapshot = _group(admin: admin);
      await _pump(tester, AsyncData(snapshot), target: snapshot.target);
      expect(find.byTooltip('admin'), admin ? findsOneWidget : findsNothing);
    }
  });

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

  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets('$palette: the panel lies on the panel level', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(
          tester,
          Theme(
              data: buildMoshTheme(colors),
              child: Scaffold(
                  body: ConversationDetailsPanel(
                      target: const DmTarget('dm'),
                      async: AsyncData(_dm()),
                      onClose: () {},
                      onOpenAttachment: (_, __, ___) {}))),
          overrides: [gatewayProvider.overrideWithValue(ScriptableGateway())]);
      final panel = tester.widget<Material>(find
          .descendant(
              of: find.byType(ConversationDetailsPanel),
              matching: find.byType(Material))
          .first);
      expect(panel.color, colors.surfaceContainerLow);
      // The head is as tall as the bar at the top of the conversation.
      expect(tester.getSize(find.byType(PanelHead)).height, 64);
      // Widget tests run as a phone, whose controls are 48 px.
      expect(tester.getSize(find.byTooltip('Close')), const Size.square(48));
    });
  }
}
