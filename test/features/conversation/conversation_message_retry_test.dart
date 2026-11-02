// The Retry row under a message that failed to send.
//
// It shows only for a message the local device sent, that failed, that the
// runtime says can be sent again, and that has an id. Tapping it asks the
// Gateway to send that message again.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

final BigInt _sentAt = BigInt.from(1700000000000);

TestMessage _failed({required String messageId}) => TestMessage.own(
      body: 'boom',
      messageId: messageId,
      sentAtMs: _sentAt,
      deliveryStatus: MessageDeliveryStatus.failed,
      deliveryError: 'peer offline',
      retryable: true,
    );

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets('$label: tapping Retry sends that message again',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(
        tester,
        testCase,
        gateway: gateway,
        messages: [_failed(messageId: 'm-retry-1')],
      );

      expect(gateway.countOf(GatewayMethod.retry), 0);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(gateway.lastCall(GatewayMethod.retry)?.target, testCase.target);
      expect(
        gateway.lastCall(GatewayMethod.retry)?.arg<String>('messageId'),
        'm-retry-1',
      );
    });
  }
}
