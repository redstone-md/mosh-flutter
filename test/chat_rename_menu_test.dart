import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/chat_row_menu.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/util/format.dart' show shorten;
import 'support/message_builders.dart';
import 'support/conversation_cases.dart';
import 'support/gateway_snapshots.dart';
import 'support/pump.dart';
import 'support/scriptable_gateway.dart';
import 'support/scriptable_bridge.dart';

void main() {
  testWidgets('an unnamed group row and rename field use the same name',
      (tester) async {
    final gateway = ScriptableGateway();
    final entry = GroupRailEntry(TestSnapshots.group(
        groupId: 'group-with-a-long-id',
        deviceFingerprint: 'fp',
        messages: const []));
    await pumpScreen(
        tester,
        Scaffold(
            body: ChatRowMenu(
                entry: entry,
                child: Builder(
                    builder: (context) => entry.buildRow(context,
                        (unreadCount: 0, active: false, onSelect: null))))),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations))
        ]);
    final displayed = shorten(entry.group.groupId, 6);
    expect(find.text(displayed), findsOneWidget);
    final gesture = await tester.startGesture(
        tester.getCenter(find.text(displayed)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename chat'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.descendant(
        of: find.byType(RenameChatDialog), matching: find.byType(TextField)));
    expect(input.controller!.text, displayed);
  });
  for (final testCase in conversationCases().take(2)) {
    testWidgets(
        '${testCase.label} header saves a personal name and reset restores identity',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, testCase, gateway: gateway);
      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename chat'));
      await tester.pumpAndSettle();
      final input = find.descendant(
          of: find.byType(RenameChatDialog), matching: find.byType(TextField));
      await tester.enterText(input, 'Family');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Family'), findsOneWidget);
      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset name'));
      await tester.pumpAndSettle();
      expect(find.text('Family'), findsNothing);
      expect(
          gateway.lastCall(GatewayMethod.resetName)!.target, testCase.target);
    });
  }

  testWidgets(
      'list context menu opens rename without selecting the conversation',
      (tester) async {
    final gateway = ScriptableGateway();
    final entry = DmRailEntry(fakeSession(
        sessionId: 'session',
        displayName: 'me',
        role: 'alice',
        fingerprint: 'fp',
        inviteUri: ''));
    await pumpScreen(
        tester,
        Scaffold(
            body: ChatRowMenu(
                entry: entry,
                child: const SizedBox(
                    width: 300, height: 70, child: Text('Chat row')))),
        overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations))
        ]);
    final gesture = await tester.startGesture(
        tester.getCenter(find.text('Chat row')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename chat'));
    await tester.pumpAndSettle();
    expect(find.byType(RenameChatDialog), findsOneWidget);
    expect(gateway.countOf(GatewayMethod.rename), 0);
  });

  testWidgets(
      'group members have no rename action and history renders a system event',
      (tester) async {
    final testCase = conversationCases().last;
    await pumpConversation(tester, testCase,
        gateway: ScriptableGateway(),
        messages: [
          const TestMessage(
              fromDevice: 'Alice',
              messageId: 'rename',
              nameChange: GroupNameChanged(name: 'Plans')),
        ]);
    expect(find.text('Alice changed the group name to Plans'), findsOneWidget);
    await tester.tap(find.byTooltip('More chat actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rename chat'), findsNothing);
  });
}
