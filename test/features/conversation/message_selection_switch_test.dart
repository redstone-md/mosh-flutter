import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/message_deletion_controls.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/gateway_snapshots.dart';
import '../../support/pump.dart';
import '../../support/scriptable_gateway.dart';

final _deleted = DeleteMessagesResult(
    deletedCount: BigInt.one,
    localOnlyCount: BigInt.zero,
    pendingCount: BigInt.zero);

DmConversation _snapshot(String id) => DmConversation(
    DmTarget(id),
    withMessage(
        fakeSession(
            sessionId: id,
            displayName: 'me',
            role: 'inviter',
            inviteUri: '',
            fingerprint: 'key'),
        'message $id',
        id,
        BigInt.one));

Future<void> _confirmDeletion(WidgetTester tester, Finder action) async {
  await tester.tap(action);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete for me'));
  await tester.pumpAndSettle();
}

Widget _controls(DmConversation snapshot) => Scaffold(
    body: MessageDeletionControls(
        snapshot: snapshot,
        builder: (context, selected, selecting, select, delete) => Column(
              children: [
                TextButton(
                    onPressed: () => select(snapshot.messages.single),
                    child: const Text('Select current')),
                TextButton(
                    onPressed: () => delete(snapshot.messages.single),
                    child: const Text('Delete current')),
              ],
            )));

void main() {
  for (final oldFails in [false, true]) {
    testWidgets('switching chats isolates pending deletion, failure=$oldFails',
        (tester) async {
      final first = Completer<DeleteMessagesResult>();
      final second = Completer<DeleteMessagesResult>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.deleteMessages, first.future)
        ..respondNext(GatewayMethod.deleteMessages, second.future);
      var snapshot = _snapshot('first');
      late StateSetter update;
      await pumpScreen(tester, StatefulBuilder(builder: (context, setState) {
        update = setState;
        return _controls(snapshot);
      }), overrides: [gatewayProvider.overrideWithValue(gateway)]);
      await _confirmDeletion(tester, find.text('Delete current'));
      update(() => snapshot = _snapshot('second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select current'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 1'), findsOneWidget);
      await _confirmDeletion(tester, find.byTooltip('Delete…'));
      if (oldFails) {
        first.completeError(Exception('old chat failure'));
      } else {
        first.complete(_deleted);
      }
      await tester.pumpAndSettle();
      expect(find.text('Selected: 1'), findsOneWidget);
      final deleteButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Delete…');
      expect(tester.widget<IconButton>(deleteButton).onPressed, isNull);
      expect(find.textContaining('Could not delete messages'), findsNothing);
      second.complete(_deleted);
      await tester.pumpAndSettle();
      expect(find.text('Selected: 1'), findsNothing);
      expect(gateway.callsTo(GatewayMethod.deleteMessages).map((c) => c.target),
          [const DmTarget('first'), const DmTarget('second')]);
    });
  }
}
