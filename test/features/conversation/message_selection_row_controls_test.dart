import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/attachment_actions.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';
import '../../support/scriptable_gateway.dart';

final _controls = [
  (
    'download',
    find.descendant(
        of: find.byType(AttachmentActions),
        matching: find.byIcon(Icons.download)),
    GatewayMethod.downloadAttachment,
    TestMessage(
        messageId: 'file', attachment: testAttachment(attachmentId: 'file')),
    <AttachmentView>[],
  ),
  (
    'cancel download',
    find.descendant(
        of: find.byType(AttachmentActions), matching: find.byIcon(Icons.close)),
    GatewayMethod.cancelAttachment,
    TestMessage(
        messageId: 'file', attachment: testAttachment(attachmentId: 'file')),
    [
      testAttachmentView(
          attachmentId: 'file',
          state: AttachmentState.downloading,
          chunkCount: 10,
          completedChunks: 2),
    ],
  ),
  (
    'retry',
    find.text('Retry'),
    GatewayMethod.retry,
    const TestMessage.own(
        body: 'failed text',
        messageId: 'failed',
        deliveryStatus: MessageDeliveryStatus.failed,
        retryable: true),
    <AttachmentView>[],
  ),
];

void main() {
  for (final conversation in conversationCases()) {
    for (final (label, control, method, message, attachments) in _controls) {
      testWidgets(
          '${conversation.label}: selection blocks keyboard $label and restores it on Cancel',
          (tester) async {
        final gateway = ScriptableGateway();
        await pumpConversation(tester, conversation,
            gateway: gateway,
            messages: [
              message,
              const TestMessage(body: 'pick this', messageId: 'pick'),
            ],
            attachments: attachments);
        final focus = Focus.of(tester.element(control));
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        await startMessageSelection(tester, 'pick this');
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(gateway.countOf(method), 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(Focus.of(tester.element(control)), same(focus));
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(gateway.countOf(method), 1);
      }, variant: TargetPlatformVariant.desktop());
    }
  }
}
