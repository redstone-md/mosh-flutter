import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final conversation in conversationCases()) {
    testWidgets('${conversation.label}: captioned files open on long press',
        (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, conversation, gateway: gateway, messages: [
        TestMessage(
            body: 'caption',
            messageId: 'file',
            attachment: testAttachment(attachmentId: 'file')),
      ]);
      await tester.longPress(find.text('report.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Select message'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
      expect(gateway.lastCall(GatewayMethod.downloadAttachment), isNull);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.download));
      await tester.pumpAndSettle();
      expect(gateway.lastCall(GatewayMethod.downloadAttachment), isNotNull);
    }, variant: TargetPlatformVariant.mobile());

    for (final caption in [false, true]) {
      testWidgets(
          '${conversation.label}: triple click copies the whole '
          '${caption ? 'caption' : 'body'} without metadata', (tester) async {
        final copied = captureClipboard(tester);
        const body = 'first word\nsecond paragraph';
        await pumpConversation(tester, conversation, messages: [
          TestMessage(
              body: body,
              messageId: 'm1',
              sentAtMs: BigInt.from(1700000000000),
              attachment:
                  caption ? testAttachment(attachmentId: 'file') : null),
          const TestMessage(body: 'neighbour', messageId: 'm2'),
        ]);
        final point = tester.getTopLeft(find.text(body)) + const Offset(8, 8);
        for (var i = 0; i < 3; i++) {
          await clickMessage(tester, point);
        }
        await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
        expect(copied, [body]);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.desktop());
    }

    testWidgets(
        '${conversation.label}: secondary click on a download control '
        'opens the menu without downloading', (tester) async {
      final gateway = ScriptableGateway();
      await pumpConversation(tester, conversation, gateway: gateway, messages: [
        TestMessage(
            messageId: 'file',
            attachment: testAttachment(attachmentId: 'file')),
      ]);
      final control = find.byIcon(Icons.download);
      expect(control, findsOneWidget);
      await tester.tap(control,
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Delete…'), findsOneWidget);
      expect(gateway.lastCall(GatewayMethod.downloadAttachment), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(gateway.lastCall(GatewayMethod.downloadAttachment), isNotNull);
    });
  }

  for (final caption in [false, true]) {
    testWidgets(
        'mobile ${caption ? 'caption' : 'text'} selection handles remain draggable with a Mosh menu',
        (tester) async {
      final copied = captureClipboard(tester);
      await pumpConversation(tester, conversationCases().first, messages: [
        TestMessage(
            body: 'first word',
            messageId: 'm1',
            attachment: caption ? testAttachment(attachmentId: 'file') : null),
      ]);
      var paragraph = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.text('first word'), matching: find.byType(RichText)));
      final point = paragraph.localToGlobal(const Offset(8, 8));
      await tester.longPressAt(point);
      await tester.pumpAndSettle();
      expect(find.text('Copy selected text'), findsOneWidget);
      paragraph = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.text('first word'), matching: find.byType(RichText)));
      final selection = paragraph.selections.single;
      expect(selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      final handle = paragraph.localToGlobal(paragraph
          .getBoxesForSelection(selection)
          .single
          .toRect()
          .bottomRight);
      final detectors = find.descendant(
          of: find.byType(CompositedTransformFollower),
          matching: find.byType(GestureDetector));
      final handlePoint = detectors.evaluate().isEmpty
          ? handle
          : tester.getCenter(detectors.last);
      final gesture = await tester.startGesture(handlePoint);
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      paragraph = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.text('first word'), matching: find.byType(RichText)));
      expect(paragraph.selections.single.extentOffset, greaterThan(5));
      final selectedText = paragraph.selections.single.textInside('first word');
      await tester.tap(find.text('Copy selected text'));
      await tester.pumpAndSettle();
      expect(copied, [selectedText]);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.mobile());
  }
}
