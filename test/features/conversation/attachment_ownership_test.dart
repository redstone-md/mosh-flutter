import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_icons.dart';
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
    testWidgets(
        '${testCase.label}: own video/mp4 without transfer state does not download or open',
        (tester) async {
      final gateway = ScriptableGateway();
      final file = testAttachment(attachmentId: 'own-media', mime: 'video/mp4');
      await pumpConversation(tester, testCase,
          gateway: gateway, messages: [TestMessage.own(attachment: file)]);

      await tester.tap(_rowIcon(true, MoshIcons.file));
      await tester.pump();

      expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
      expect(find.byType(MediaViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${testCase.label}: each row retains its ownership for the same attachment id',
        (tester) async {
      final gateway = ScriptableGateway();
      final file = testAttachment(attachmentId: 'shared-id', mime: 'image/png');
      await pumpConversation(tester, testCase, gateway: gateway, messages: [
        TestMessage.own(messageId: 'own', attachment: file),
        TestMessage(messageId: 'incoming', attachment: file),
      ]);

      await tester.tap(_rowIcon(true, MoshIcons.file));
      await tester.pump();
      expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
      expect(find.byType(MediaViewer), findsNothing);

      expect(tester.takeException(), isNull);

      await tester.tap(_rowIcon(false, MoshIcons.download));
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

        await tester.tap(_rowIcon(own, MoshIcons.play));
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

        await tester.tap(_rowIcon(
            !outgoing, outgoing ? MoshIcons.file : MoshIcons.download));
        await tester.pump();

        expect(gateway.countOf(GatewayMethod.downloadAttachment),
            outgoing ? 0 : 1);
        expect(find.byType(MediaViewer), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '${testCase.label}: a downloaded video opens in the viewer under its sender and time',
        (tester) async {
      final file = testAttachment(attachmentId: 'clip', mime: 'video/mp4');
      final sentAt = DateTime(2026, 11, 21, 9, 38);
      await pumpConversation(tester, testCase, messages: [
        TestMessage(
            fromDevice: 'Maya Chen',
            sentAtMs: BigInt.from(sentAt.millisecondsSinceEpoch),
            attachment: file),
      ], attachments: [
        testAttachmentView(
            attachmentId: 'clip',
            state: AttachmentState.available,
            localPath: '/downloads/clip.mp4'),
      ]);

      await tester.tap(_rowIcon(false, MoshIcons.file));
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byType(MediaViewer),
              matching: find.text('Maya Chen, Nov 21, 2026 09:38')),
          findsOneWidget);
      // A file that is here can be saved from the bar.
      expect(
          tester
              .widget<IconButton>(
                  find.widgetWithIcon(IconButton, MoshIcons.download))
              .onPressed,
          isNotNull);
    });

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

      await tester.tap(_rowIcon(false, MoshIcons.close));
      await tester.pump();

      expect(gateway.countOf(GatewayMethod.cancelAttachment), 1);
      expect(gateway.countOf(GatewayMethod.downloadAttachment), 0);
      expect(tester.takeException(), isNull);
    });
  }
}
