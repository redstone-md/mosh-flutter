import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/conversation_cases.dart';
import '../../support/scriptable_gateway.dart';

Finder _rowIcon(bool own, IconData icon) => find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is ConversationMessageRow && widget.message.own == own),
      matching: find.byIcon(icon),
    );

AttachmentDescriptor _voice() => AttachmentDescriptor(
    attachmentId: 'voice',
    contentHash: 'voice-hash',
    fileName: 'voice.m4a',
    mime: 'audio/mp4',
    totalSize: BigInt.from(1024),
    voice: const VoiceMeta(durationMs: 4200, peaksB64: ''));

void main() {
  for (final testCase in conversationCases()) {
    for (final mime in ['image/png', 'video/mp4']) {
      testWidgets(
          '${testCase.label}: own $mime without transfer state does not download or open',
          (tester) async {
        final gateway = ScriptableGateway();
        final file = testAttachment(attachmentId: 'own-media', mime: mime);
        await pumpConversation(tester, testCase,
            gateway: gateway, messages: [TestMessage.own(attachment: file)]);

        await tester.tap(_rowIcon(
            true,
            mime.startsWith('image/')
                ? Icons.image_outlined
                : Icons.play_arrow));
        await tester.pump();

        expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
        expect(find.byType(MediaViewer), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '${testCase.label}: each row retains its ownership for the same attachment id',
        (tester) async {
      final gateway = ScriptableGateway();
      final file = testAttachment(attachmentId: 'shared-id', mime: 'image/png');
      await pumpConversation(tester, testCase, gateway: gateway, messages: [
        TestMessage.own(messageId: 'own', attachment: file),
        TestMessage(messageId: 'incoming', attachment: file),
      ]);

      await tester.tap(_rowIcon(true, Icons.image_outlined));
      await tester.pump();
      expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
      expect(find.byType(MediaViewer), findsNothing);

      await tester.tap(_rowIcon(false, Icons.image_outlined));
      await tester.pump();
      expect(gateway.countOf(GatewayMethod.downloadAttachment), 1);
      expect(find.byType(MediaViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final own in [true, false]) {
      testWidgets(
          '${testCase.label}: own=$own voice uses message ownership without transfer state',
          (tester) async {
        final gateway = ScriptableGateway();
        final voice = _voice();
        await pumpConversation(tester, testCase, gateway: gateway, messages: [
          own
              ? TestMessage.own(attachment: voice)
              : TestMessage(attachment: voice),
        ]);

        await tester.tap(_rowIcon(own, Icons.play_arrow_rounded));
        await tester.pump();

        expect(gateway.countOf(GatewayMethod.downloadAttachment), own ? 0 : 1);
        expect(tester.takeException(), isNull);
      });
    }

    for (final outgoing in [true, false]) {
      testWidgets(
          '${testCase.label}: runtime outgoing=$outgoing direction overrides message ownership',
          (tester) async {
        final gateway = ScriptableGateway();
        final image = testAttachment(attachmentId: 'image', mime: 'image/png');
        await pumpConversation(tester, testCase, gateway: gateway, messages: [
          outgoing
              ? TestMessage(attachment: image)
              : TestMessage.own(attachment: image),
        ], attachments: [
          testAttachmentView(
              attachmentId: 'image',
              direction: outgoing ? 'outgoing' : 'incoming',
              state: AttachmentState.offered),
        ]);

        await tester.tap(_rowIcon(!outgoing, Icons.image_outlined));
        await tester.pump();

        expect(gateway.countOf(GatewayMethod.downloadAttachment),
            outgoing ? 0 : 1);
        expect(find.byType(MediaViewer), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '${testCase.label}: incoming transfers keep their cancel action',
        (tester) async {
      final gateway = ScriptableGateway();
      final file = testAttachment(attachmentId: 'incoming-download');
      await pumpConversation(tester, testCase, gateway: gateway, messages: [
        TestMessage(attachment: file),
      ], attachments: [
        testAttachmentView(
            attachmentId: file.attachmentId,
            state: AttachmentState.downloading,
            completedChunks: 1,
            chunkCount: 2),
      ]);

      await tester.tap(_rowIcon(false, Icons.close));
      await tester.pump();

      expect(gateway.countOf(GatewayMethod.cancelAttachment), 1);
      expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
      expect(tester.takeException(), isNull);
    });
  }
}
