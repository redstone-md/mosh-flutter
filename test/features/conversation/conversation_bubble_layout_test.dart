import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';

import '../../support/contrast.dart';
import '../../support/pump.dart';
import '../../support/conversation_cases.dart';

final _sentAt = BigInt.from(1700000000000);

Future<void> _pumpBubble(WidgetTester tester, String body,
        {double width = 320,
        double scale = 1,
        bool own = false,
        bool accessibilitySpacing = false,
        bool showTime = true,
        TextDirection direction = TextDirection.ltr}) =>
    pumpScreen(
      tester,
      Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              boldText: accessibilitySpacing,
              lineHeightScaleFactorOverride: accessibilitySpacing ? 1.8 : null,
              letterSpacingOverride: accessibilitySpacing ? 2 : null,
              wordSpacingOverride: accessibilitySpacing ? 4 : null),
          child: Directionality(
              textDirection: direction,
              child: Center(
                child: SizedBox(
                  width: width,
                  child: ConversationMessageRow(
                    message: ConversationMessage(
                      fromDevice: 'bob',
                      body: body,
                      own: own,
                      sentAtMs: showTime ? _sentAt : null,
                      deliveryStatus: MessageDeliveryStatus.delivered,
                    ),
                    kind: ConversationKind.dm,
                    grouped: false,
                    busy: false,
                    onAttachmentDownload: (_) {},
                    onAttachmentCancel: (_) {},
                    onAttachmentOpen: (_) {},
                    onRetry: (_) {},
                    l: lookupAppLocalizations(const Locale('en')),
                  ),
                ),
              )),
        ),
      ),
    );

Rect _lastTextLine(WidgetTester tester, String body) {
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(body), matching: find.byType(RichText)));
  final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: body.length));
  return boxes.last.toRect().shift(paragraph.localToGlobal(Offset.zero));
}

Rect _clock(WidgetTester tester) =>
    tester.getRect(find.text(formatClock(_sentAt, locale: 'en')!));

void main() {
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: bubble corners and gaps follow sender blocks',
        (tester) async {
      await pumpConversation(tester, testCase, messages: [
        TestMessage(body: 'first', sentAtMs: _sentAt),
        TestMessage(body: 'second', sentAtMs: _sentAt + BigInt.one),
        TestMessage.own(body: 'third', sentAtMs: _sentAt + BigInt.two),
        TestMessage.own(body: 'fourth', sentAtMs: _sentAt + BigInt.from(3)),
      ]);
      BorderRadius corners(String body) {
        final bubble = tester
            .widget<Container>(find.byKey(ValueKey('message-bubble-$body')));
        return (bubble.decoration as BoxDecoration)
            .borderRadius!
            .resolve(TextDirection.ltr);
      }

      expect(corners('first').topLeft, const Radius.circular(20));
      expect(corners('first').bottomLeft, const Radius.circular(8));
      expect(corners('second').topLeft, const Radius.circular(8));
      expect(corners('second').bottomLeft, const Radius.circular(20));
      expect(corners('third').bottomRight, const Radius.circular(8));
      expect(corners('fourth').topRight, const Radius.circular(8));
      final first =
          tester.getRect(find.byKey(const ValueKey('message-bubble-first')));
      final second =
          tester.getRect(find.byKey(const ValueKey('message-bubble-second')));
      expect(second.top - first.bottom, closeTo(4, 0.01));
    });
  }
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: only a group and a channel put an avatar beside '
        'the first bubble of a run', (tester) async {
      await pumpConversation(tester, testCase, messages: [
        TestMessage(body: 'first', sentAtMs: _sentAt),
        TestMessage(body: 'second', sentAtMs: _sentAt + BigInt.one),
      ]);
      final feed = find.byType(ConversationMessageRow);
      expect(find.descendant(of: feed, matching: find.byType(Avatar)),
          testCase.label == 'DM' ? findsNothing : findsOneWidget);
    });
  }

  for (final own in [false, true]) {
    testWidgets('the text of a bubble reads on its fill (own=$own)',
        (tester) async {
      await _pumpBubble(tester, 'hello', own: own);
      final bubble = tester.widget<Container>(
          find.byKey(const ValueKey('message-bubble-hello')));
      final fill = (bubble.decoration as BoxDecoration).color!;
      for (final text in ['hello', formatClock(_sentAt, locale: 'en')!]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
            of: find.text(text), matching: find.byType(RichText)));
        expect(contrastRatio(paragraph.text.style!.color!, fill),
            greaterThanOrEqualTo(4.5),
            reason: text);
      }
    });
  }

  testWidgets('a token without spaces breaks inside the measure',
      (tester) async {
    final body = 'mosh1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh' * 3;
    await _pumpBubble(tester, body, width: 760, own: true);
    final bubble = tester.getRect(find.byKey(ValueKey('message-bubble-$body')));
    final text = tester.getRect(find.text(body));
    expect(text.width, lessThanOrEqualTo(480));
    expect(bubble.contains(text.topLeft) && bubble.contains(text.bottomRight),
        isTrue);
    expect(text.height, greaterThan(24));
  });

  // The last case's bubble has to grow past its longest line to fit the time.
  for (final body in ['hello', 'a longer first line\nok', 'ok\nabcdef']) {
    testWidgets('time shares the last line when it fits: $body',
        (tester) async {
      await _pumpBubble(tester, body, own: true);
      final line = _lastTextLine(tester, body);
      final clock = _clock(tester);
      expect(clock.center.dy, inInclusiveRange(line.top, line.bottom));
      expect(clock.left, greaterThan(line.right));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('DM messages do not repeat the contact name', (tester) async {
    await _pumpBubble(tester, 'hello');
    expect(find.text('bob'), findsNothing);
  });

  testWidgets('bold text and accessibility spacing preserve inline separation',
      (tester) async {
    await _pumpBubble(tester, 'hello', own: true, accessibilitySpacing: true);
    final line = _lastTextLine(tester, 'hello');
    final clock = _clock(tester);
    expect(clock.left, greaterThan(line.right));
    expect(clock.center.dy, inInclusiveRange(line.top, line.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL text places time on the trailing side without overlap',
      (tester) async {
    const body = 'مرحبا';
    await _pumpBubble(tester, body, direction: TextDirection.rtl);
    final line = _lastTextLine(tester, body);
    final clock = _clock(tester);
    expect(clock.right, lessThan(line.left));
    expect(clock.center.dy, inInclusiveRange(line.top, line.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final own in [false, true]) {
    testWidgets('missing time is not invented (own=$own)', (tester) async {
      await _pumpBubble(tester, 'hello', own: own, showTime: false);
      expect(find.text(formatClock(_sentAt, locale: 'en')!), findsNothing);
      expect(
          find.byIcon(MoshIcons.doneAll), own ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a full last line puts time below the text without overlap',
      (tester) async {
    const body = 'abcdefghijklmn';
    await _pumpBubble(tester, body, width: 280, own: true);
    final line = _lastTextLine(tester, body);
    expect(_clock(tester).top, greaterThanOrEqualTo(line.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and a narrow bubble keep content and ticks inside',
      (tester) async {
    const body = 'Текст с переносом\nи окончанием';
    await _pumpBubble(tester, body, width: 260, scale: 2, own: true);
    final bubble = tester.getRect(find.byKey(ValueKey('message-bubble-$body')));
    expect(_clock(tester).right, lessThanOrEqualTo(bubble.right - 10));
    expect(tester.getRect(find.byIcon(MoshIcons.doneAll)).right,
        lessThanOrEqualTo(bubble.right - 10));
    expect(tester.takeException(), isNull);
  });
}
