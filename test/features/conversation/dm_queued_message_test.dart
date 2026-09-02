// A DM text never fails and never asks to be retried: while it waits for
// the contact it shows a clock, and the Retry row stays reserved for a
// `failed` message -- which an attachment can still be.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/conversation_cases.dart';

final BigInt _sentAt = BigInt.from(1700000000000);

ConversationCase _dm() =>
    conversationCases().singleWhere((c) => c.label == 'DM');

void main() {
  testWidgets('a queued text shows a clock and no Retry', (tester) async {
    await pumpConversation(
      tester,
      _dm(),
      messages: [
        TestMessage.own(
          body: 'typed while offline',
          messageId: 'm-queued',
          sentAtMs: _sentAt,
          deliveryStatus: MessageDeliveryStatus.queued,
          retryable: false,
        ),
      ],
    );

    expect(find.text('typed while offline'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.text('queued'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Failed to send'), findsNothing);
  });

  testWidgets('a failed attachment still shows Retry', (tester) async {
    await pumpConversation(
      tester,
      _dm(),
      messages: [
        TestMessage.own(
          messageId: 'm-file',
          sentAtMs: _sentAt,
          attachment: testAttachment(attachmentId: 'a-file'),
          deliveryStatus: MessageDeliveryStatus.failed,
          deliveryError: 'no live path',
          retryable: true,
        ),
      ],
    );

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('no live path'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
