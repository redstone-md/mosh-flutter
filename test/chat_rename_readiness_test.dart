import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/chat_row_menu.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/rust/chat_names/types.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'support/conversation_cases.dart';
import 'support/message_builders.dart';
import 'support/pump.dart';
import 'support/scriptable_bridge.dart';
import 'support/scriptable_gateway.dart';

class _Names extends ChatNamesNotifier {
  _Names(this.canRename);
  final bool canRename;

  @override
  Future<ChatNameSnapshot> build() async =>
      ChatNameSnapshot(entries: const [], pending: true, canRename: canRename);
}

void main() {
  for (final canRename in [false, true]) {
    for (final testCase in conversationCases().take(2)) {
      testWidgets('${testCase.label} header follows canRename=$canRename',
          (tester) async {
        final gateway = ScriptableGateway();
        await pumpScreen(tester, testCase.screen, overrides: [
          gatewayProvider.overrideWithValue(gateway),
          bridgeFacadeProvider.overrideWithValue(
              ScriptableBridge(conversations: gateway.conversations)),
          testCase.snapshotOverride(messages: const [], attachments: const []),
          chatNamesProvider.overrideWith(() => _Names(canRename)),
        ]);
        await tester.tap(find.byTooltip('More chat actions'));
        await tester.pumpAndSettle();
        final button = tester.widget<MenuItemButton>(find.ancestor(
            of: find.text('Rename chat'),
            matching: find.byType(MenuItemButton)));
        expect(button.onPressed, canRename ? isNotNull : isNull);
        if (canRename) {
          await tester.tap(find.text('Rename chat'));
          await tester.pumpAndSettle();
          expect(find.byType(RenameChatDialog), findsOneWidget);
        }
      });
    }

    testWidgets('list rename follows canRename=$canRename', (tester) async {
      final gateway = ScriptableGateway();
      final entry = DmRailEntry(TestSnapshots.dm(sessionId: 'session'));
      await pumpScreen(
          tester,
          Scaffold(
              body: ChatRowMenu(
                  entry: entry,
                  child: const SizedBox(
                      width: 300, height: 70, child: Text('Chat row')))),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            chatNamesProvider.overrideWith(() => _Names(canRename)),
          ]);
      final gesture = await tester.startGesture(
          tester.getCenter(find.text('Chat row')),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton);
      await gesture.up();
      await tester.pumpAndSettle();
      final button = tester.widget<MenuItemButton>(find.ancestor(
          of: find.text('Rename chat'), matching: find.byType(MenuItemButton)));
      expect(button.onPressed, canRename ? isNotNull : isNull);
    });
  }
}
