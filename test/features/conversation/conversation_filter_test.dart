// The search box and the All/Files filter: what they keep, and that the
// screen filters before it groups, so a hidden message cannot bridge two
// blocks. Plus the width at which the layout turns mobile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentDescriptor;

import '../../support/conversation_cases.dart';
import '../../support/pump.dart';

ConversationMessage _message({
  required String from,
  required String body,
  AttachmentDescriptor? attachment,
}) =>
    ConversationMessage(
      fromDevice: from,
      body: body,
      own: false,
      attachment: attachment,
    );

void main() {
  final report = testAttachment(attachmentId: 'att-1');
  final clip = testAttachment(
    attachmentId: 'att-2',
    fileName: 'clip.mp4',
    mime: 'video/mp4',
  );

  final alicePlain = _message(from: 'alice', body: 'hello world');
  final bobPlain = _message(from: 'bob', body: 'how are you');
  final aliceReport =
      _message(from: 'alice', body: 'here is the report', attachment: report);
  final bobClip = _message(from: 'bob', body: 'a clip', attachment: clip);

  group('filterConversationMessages', () {
    test('no search and no filter keeps everything', () {
      final input = [alicePlain, bobPlain];
      expect(
        filterConversationMessages(input, '', ConversationFilter.all),
        equals(input),
      );
    });

    test('the Files filter keeps only messages with a file', () {
      expect(
        filterConversationMessages(
          [alicePlain, aliceReport, bobClip],
          '',
          ConversationFilter.attachments,
        ),
        [aliceReport, bobClip],
      );
    });

    test('search matches the sender name, whatever the case', () {
      expect(
        filterConversationMessages(
          [alicePlain, bobPlain, aliceReport],
          'ALICE',
          ConversationFilter.all,
        ),
        [alicePlain, aliceReport],
      );
    });

    test('search matches the file name', () {
      expect(
        filterConversationMessages(
          [alicePlain, aliceReport],
          'report',
          ConversationFilter.all,
        ),
        [aliceReport],
      );
    });

    test('search matches the file type', () {
      expect(
        filterConversationMessages(
          [alicePlain, aliceReport],
          'pdf',
          ConversationFilter.all,
        ),
        [aliceReport],
      );
    });

    test('search is trimmed', () {
      expect(
        filterConversationMessages(
          [alicePlain, bobPlain],
          '  hello  ',
          ConversationFilter.all,
        ),
        [alicePlain],
      );
    });

    test('a search that matches nothing keeps nothing', () {
      expect(
        filterConversationMessages(
          [alicePlain, bobPlain],
          'nothing like this',
          ConversationFilter.all,
        ),
        isEmpty,
      );
    });

    test('the Files filter and a search both apply', () {
      expect(
        filterConversationMessages(
          [alicePlain, bobPlain, bobClip],
          'bob',
          ConversationFilter.attachments,
        ),
        [bobClip],
      );
    });

    test('the fingerprint is not searchable', () {
      const message = ConversationMessage(
        fromDevice: 'alice',
        fromFingerprint: 'fp-secret',
        body: 'hello',
        own: false,
      );
      expect(
        filterConversationMessages(
          [message],
          'fp-secret',
          ConversationFilter.all,
        ),
        isEmpty,
      );
    });
  });

  for (final testCase in conversationCases()) {
    testWidgets('${testCase.label}: typing a search hides the other messages',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [
          const TestMessage(body: 'hello'),
          TestMessage(body: 'see this', attachment: report),
        ],
      );

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('see this'), findsOneWidget);

      // The search box is the first text field on the screen; the composer
      // is the other one.
      await tester.enterText(find.byType(TextField).first, 'report');
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsNothing);
      expect(find.text('see this'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
    });
  }

  group('isMobileBreakpoint', () {
    Future<bool?> resultAtWidth(WidgetTester tester, double width) async {
      bool? result;
      await pumpScreen(
        tester,
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              result = isMobileBreakpoint(context);
              return const SizedBox.shrink();
            },
          ),
        ),
        settle: false,
      );
      return result;
    }

    testWidgets('580 wide is mobile', (tester) async {
      expect(await resultAtWidth(tester, 580), isTrue);
    });

    testWidgets('581 wide is not', (tester) async {
      expect(await resultAtWidth(tester, 581), isFalse);
    });

    testWidgets('400 wide is mobile', (tester) async {
      expect(await resultAtWidth(tester, 400), isTrue);
    });

    testWidgets('800 wide is not', (tester) async {
      expect(await resultAtWidth(tester, 800), isFalse);
    });
  });
}
