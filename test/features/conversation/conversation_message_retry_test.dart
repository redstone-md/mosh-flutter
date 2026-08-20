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

TestMessage _failed({
  String? messageId = 'm1',
  String? deliveryError = 'peer offline',
  bool? retryable = true,
  MessageDeliveryStatus? deliveryStatus = MessageDeliveryStatus.failed,
}) =>
    TestMessage.own(
      body: 'boom',
      messageId: messageId,
      sentAtMs: _sentAt,
      deliveryStatus: deliveryStatus,
      deliveryError: deliveryError,
      retryable: retryable,
    );

void main() {
  for (final testCase in conversationCases()) {
    final label = testCase.label;

    testWidgets(
        '$label: an own failed message that can be sent again shows '
        'the error and Retry', (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [_failed(deliveryError: '  peer offline  ')],
      );

      expect(find.text('boom'), findsOneWidget);
      // The error is trimmed before it is shown.
      expect(find.text('peer offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('$label: with no error text it falls back to "Failed to send"',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [_failed(deliveryError: null)],
      );

      expect(find.text('Failed to send'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('$label: a message that did not fail shows no Retry',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [
          _failed(
              deliveryStatus: MessageDeliveryStatus.sent, deliveryError: null),
        ],
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('$label: a failure the runtime will not retry shows no Retry',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [_failed(retryable: false)],
      );

      expect(find.text('peer offline'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('$label: a failed message with no id shows no Retry',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [_failed(messageId: null)],
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets("$label: someone else's failed message shows no Retry",
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [
          const TestMessage(
            body: 'boom',
            messageId: 'm5',
            deliveryStatus: MessageDeliveryStatus.failed,
            deliveryError: 'peer offline',
            retryable: true,
          ),
        ],
      );

      expect(find.text('Retry'), findsNothing);
    });

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
