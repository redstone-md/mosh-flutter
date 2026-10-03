import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';

ConversationMessage _msg(String id, String text, {bool own = false}) =>
    ConversationMessage(
      fromDevice: 'Alice',
      body: text,
      own: own,
      messageId: id,
      sentAtMs: BigInt.from(1700000000000),
    );

Future<void> _pumpList(
  WidgetTester tester,
  List<ConversationMessage> messages,
  DmConversation snapshot, {
  bool settle = true,
}) =>
    pumpScreen(
      tester,
      ConversationMessageListView(
        messages: messages,
        snapshot: snapshot,
        attachmentCallbacks: (_, {required bool own}) =>
            const ConversationAttachmentCallbacks(
          busy: false,
          onDownload: _noop,
          onCancel: _noop,
          onOpen: _noopOpen,
        ),
        onRetryMessage: (_) {},
      ),
      settle: settle,
    );

void _noop(String _) {}
void _noopOpen(dynamic _) {}

void main() {
  testWidgets(
      'initial messages skip animation; newly arriving message animates',
      (tester) async {
    final snapshot = DmConversation(
      const DmTarget('s1'),
      TestSnapshots.dm(sessionId: 's1'),
    );

    // Initial render with message 1: animation is skipped.
    await _pumpList(tester, [_msg('m1', 'First message')], snapshot);
    expect(find.text('First message'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );

    // Next build: message 2 arrives and animates (settle: false to catch in-flight).
    await _pumpList(
      tester,
      [_msg('m1', 'First message'), _msg('m2', 'Second message')],
      snapshot,
      settle: false,
    );
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(SlideTransition),
      ),
      findsOneWidget,
    );
    expect(find.text('Second message'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second message'), findsOneWidget);
  });
}
