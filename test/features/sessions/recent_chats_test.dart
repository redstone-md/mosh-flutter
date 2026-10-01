import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/rail_activity.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/message_builders.dart';
import '../../support/conversation_cases.dart' show testAttachment;
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

final l = lookupAppLocalizations(const Locale('en'));
final dm =
    TestSnapshots.dm(sessionId: 'dm', peerDisplayName: 'Alice', messages: [
  TestMessages.dm(
      fromDevice: 'me', body: 'first\n  message', sentAtMs: BigInt.from(20)),
  TestMessages.dm(fromDevice: 'Alice', body: '', sentAtMs: BigInt.from(100)),
  TestMessages.dm(fromDevice: 'Alice', body: 'old', sentAtMs: BigInt.one),
]);
final channel = TestSnapshots.channel(
    name: 'general',
    deviceFingerprint: 'self',
    messages: [
      TestMessages.channel(
          fromDevice: 'Bob',
          fromFingerprint: 'bob',
          body: 'channel news',
          sentAtMs: BigInt.from(30)),
    ]);
final group = TestSnapshots.group(
    groupId: 'group',
    label: 'Crew',
    deviceFingerprint: 'self',
    messages: [
      TestMessages.group(
          fromDevice: 'Charlie',
          fromFingerprint: 'charlie',
          body: 'group news',
          sentAtMs: BigInt.from(10)),
    ]);

void main() {
  test('one recent list ignores empty control events and history order', () {
    final empty = TestSnapshots.dm(sessionId: 'empty');
    final rows = recentRailEntries([
      GroupRailEntry(group),
      DmRailEntry(empty),
      DmRailEntry(dm),
      ChannelRailEntry(channel),
    ], l);
    expect(rows.map((r) => r.ref!.key),
        ['channel:general', 'dm:dm', 'group:group', 'dm:empty']);
    expect(rows[1].preview(l), 'You: first message');
    expect(rows[1].activity.sentAtMs, BigInt.from(20));
    expect(rows[0].preview(l), 'Bob: channel news');
    expect(rows[2].preview(l), 'Charlie: group news');
  });

  test('search matches titles and known participants, combines with kind', () {
    final entries = [
      DmRailEntry(dm),
      ChannelRailEntry(channel),
      GroupRailEntry(group)
    ];
    expect(
        recentRailEntries(entries, l, query: ' ALICE ').single.ref!.id, 'dm');
    expect(
        recentRailEntries(entries, l, query: 'bob').single.ref!.id, 'general');
    expect(
        recentRailEntries(entries, l, query: 'crew').single.ref!.id, 'group');
    expect(
        recentRailEntries(entries, l,
            query: 'Charlie', kind: ConversationKind.dm),
        isEmpty);
    expect(
        recentRailEntries(entries, l, kind: ConversationKind.group)
            .single
            .ref!
            .id,
        'group');
  });

  test('untimed content is retained but cannot displace dated activity', () {
    final snapshot = TestSnapshots.dm(sessionId: 'mixed', messages: [
      TestMessages.dm(fromDevice: 'Alice', body: 'undated'),
      TestMessages.dm(fromDevice: 'me', body: 'dated', sentAtMs: BigInt.one),
      TestMessages.dm(fromDevice: 'Alice', body: 'another undated'),
    ]);
    expect(RailActivity.dm(snapshot).text, 'dated');
    expect(RailActivity.dm(TestSnapshots.dm(sessionId: 'empty')).text, isNull);
  });

  test('an attachment is activity; undated active chats precede empty chats',
      () {
    final file = testAttachment(attachmentId: 'attachment');
    final attached = DmRailEntry(TestSnapshots.dm(sessionId: 'z', messages: [
      TestMessages.dm(fromDevice: 'me', body: '', attachment: file),
    ]));
    final empty = DmRailEntry(TestSnapshots.dm(sessionId: 'a'));
    expect(recentRailEntries([empty, attached], l), [attached, empty]);
    expect(attached.preview(l), 'You: report.pdf');
    expect(recentRailEntries([attached, empty], l, query: 'report'), isEmpty);
  });

  testWidgets('search and kind chips change the real unified rail',
      (tester) async {
    final gateway = ScriptableGateway()
      ..seedSessions([dm])
      ..seedChannels([channel])
      ..seedGroups([group]);
    await pumpScreen(tester, const SessionsScreen(), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(
          ScriptableBridge(conversations: gateway.conversations)),
    ]);
    List<String> titles() => tester
        .widgetList<RailItem>(find.byType(RailItem))
        .map((r) => r.title)
        .toList();
    expect(titles(), ['#general', 'Alice', 'Crew']);
    expect(find.text('You: first message'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Groups'));
    await tester.pumpAndSettle();
    expect(titles(), ['Crew']);
    await tester.enterText(find.byKey(const Key('chat-list-search')), 'Bob');
    await tester.pumpAndSettle();
    expect(find.text('No matching chats'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(titles(), ['#general']);
  });
}
