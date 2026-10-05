import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final c in conversationCases()) {
    testWidgets('${c.label}: deletion uses an explicit local scope',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, c, gateway: gateway, messages: [
        TestMessage(
            body: 'erase this message',
            messageId: 'm1',
            sentAtMs: BigInt.from(1700000000000))
      ]);
      await tester.tap(find.text('erase this message'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Delete for everyone'))
              .onPressed,
          isNull);
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(gateway.lastCall(GatewayMethod.deleteMessages)!.args['messageIds'],
          ['m1']);
      expect(gateway.lastCall(GatewayMethod.deleteMessages)!.args['scope'],
          DeleteScope.forMe);
    });
    testWidgets(
        '${c.label}: bulk deletion requires every selected message to qualify',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, c, gateway: gateway, messages: [
        TestMessage(
            body: 'eligible',
            messageId: 'm1',
            metadata: const MessageMetadata(
                canDeleteForEveryone: true, localOnly: false)),
        const TestMessage(body: 'personal only', messageId: 'm2'),
      ]);
      await tester.tap(find.text('eligible'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select message'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byWidgetPredicate((w) => w is Checkbox && w.value == false));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete…'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Delete for everyone'))
              .onPressed,
          isNull);
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(
          gateway
              .lastCall(GatewayMethod.deleteMessages)!
              .arg<List<String>>('messageIds'),
          ['m1', 'm2']);
      expect(find.text('Selected: 2'), findsNothing);
    });
    testWidgets('${c.label}: a qualifying message can be deleted for everyone',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, c, gateway: gateway, messages: [
        const TestMessage(
            body: 'own text',
            messageId: 'm1',
            metadata:
                MessageMetadata(canDeleteForEveryone: true, localOnly: false)),
      ]);
      await tester.tap(find.text('own text'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for everyone'));
      await tester.pumpAndSettle();
      expect(
          gateway
              .lastCall(GatewayMethod.deleteMessages)!
              .arg<DeleteScope>('scope'),
          DeleteScope.forEveryone);
    });

    testWidgets(
        '${c.label}: refused deletion preserves selection and shows an error',
        (tester) async {
      final gateway = ScriptableGateway()
        ..failNext(GatewayMethod.deleteMessages);
      await pumpConversation(tester, c, gateway: gateway, messages: [
        const TestMessage(body: 'keep selection', messageId: 'm1')
      ]);
      await tester.tap(find.text('keep selection'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select message'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(find.text('Selected: 1'), findsOneWidget);
      expect(find.textContaining('Could not delete messages'), findsOneWidget);
      expect(find.text('keep selection'), findsOneWidget);
    });

    testWidgets('${c.label}: files expose the same deletion menu as text',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, c, gateway: gateway, messages: [
        TestMessage(
            messageId: 'file',
            attachment: AttachmentDescriptor(
                attachmentId: 'file',
                contentHash: 'hash',
                fileName: 'report.pdf',
                mime: 'application/pdf',
                totalSize: BigInt.from(1024))),
      ]);
      await tester.tap(find.text('report.pdf'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(
          gateway
              .lastCall(GatewayMethod.deleteMessages)!
              .arg<List<String>>('messageIds'),
          ['file']);
    });

    testWidgets(
        '${c.label}: moderated placeholders show author and delivery state',
        (tester) async {
      await pumpConversation(tester, c,
          gateway: ScriptableGateway(),
          messages: [
            const TestMessage(
                messageId: 'deleted',
                metadata: MessageMetadata(
                    canDeleteForEveryone: false,
                    localOnly: false,
                    deletion: DeletionMarker(
                        scope: DeleteScope.forEveryone,
                        status: DeletionStatus.pending,
                        administrator: 'Alice'))),
          ]);
      expect(
          find.text('Message deleted by administrator Alice'), findsOneWidget);
      expect(find.text('Awaiting delivery'), findsOneWidget);
    });
  }
}
