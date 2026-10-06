import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/message_selection_bar.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/gateway_snapshots.dart';
import '../../support/hosted_message_list.dart';
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

Future<void> _menu(WidgetTester tester, String id, String action) async {
  await tester.tap(find.text('message $id'),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

/// The selection bar's count, or null when nothing is being picked.
int? _picked(WidgetTester tester) {
  final bar = find.byType(MessageSelectionBar);
  return bar.evaluate().isEmpty
      ? null
      : tester.widget<MessageSelectionBar>(bar).count;
}

void main() {
  for (final oldFails in [false, true]) {
    testWidgets('switching chats isolates pending deletion, failure=$oldFails',
        (tester) async {
      final first = Completer<DeleteMessagesResult>();
      final second = Completer<DeleteMessagesResult>();
      final gateway = ScriptableGateway()
        ..respondNext(GatewayMethod.deleteMessages, first.future)
        ..respondNext(GatewayMethod.deleteMessages, second.future);
      final snapshot = ValueNotifier<ConversationSnapshot>(_snapshot('first'));
      addTearDown(snapshot.dispose);
      await pumpScreen(tester, HostedMessageList(snapshot: snapshot),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            hostedSnapshotOverride(snapshot),
          ]);
      await _menu(tester, 'first', 'Select message');
      await _confirmDeletion(
          tester, find.widgetWithText(FilledButton, 'Delete'));
      snapshot.value = _snapshot('second');
      await tester.pumpAndSettle();
      expect(_picked(tester), isNull);
      await _menu(tester, 'second', 'Select message');
      expect(_picked(tester), 1);
      await _confirmDeletion(
          tester, find.widgetWithText(FilledButton, 'Delete'));
      if (oldFails) {
        first.completeError(Exception('old chat failure'));
      } else {
        first.complete(_deleted);
      }
      await tester.pumpAndSettle();
      expect(_picked(tester), 1);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
              .onPressed,
          isNull);
      expect(find.textContaining('Could not delete messages'), findsNothing);
      second.complete(_deleted);
      await tester.pumpAndSettle();
      expect(_picked(tester), isNull);
      expect(gateway.callsTo(GatewayMethod.deleteMessages).map((c) => c.target),
          [const DmTarget('first'), const DmTarget('second')]);
    });
  }
}
