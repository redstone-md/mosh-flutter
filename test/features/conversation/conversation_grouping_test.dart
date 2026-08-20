// Grouping: consecutive messages from one sender inside five minutes become
// one block, and only the first row of a block carries the sender meta.
//
// The unit cases drive the pure helper. The widget case runs over all three
// kinds, because each one keys the sender differently: a DM by device name,
// a channel and a group by fingerprint.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:mosh/src/features/conversation/conversation_message_list_view.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';

import '../../support/conversation_cases.dart';

final BigInt _base = BigInt.from(1700000000000); // 2023-11-14T22:13:20Z

BigInt _afterMinutes(int minutes) => _base + BigInt.from(minutes * 60 * 1000);

ConversationMessage _message({
  required String from,
  required String body,
  BigInt? sentAtMs,
}) =>
    ConversationMessage(
      fromDevice: from,
      fromFingerprint: 'fp-$from',
      body: body,
      own: false,
      sentAtMs: sentAtMs,
    );

List<bool> _groupedFlags(List<ConversationMessage> messages) =>
    groupConversationMessages(messages).map((row) => row.grouped).toList();

void main() {
  // formatClock goes through intl, and `main()` never runs under
  // `flutter test`, so load the date symbols here.
  setUpAll(initializeDateFormatting);

  group('groupConversationMessages', () {
    test('a single message never continues a block', () {
      expect(
        _groupedFlags([_message(from: 'alice', body: 'a', sentAtMs: _base)]),
        [false],
      );
    });

    test('the same sender within five minutes continues the block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _base),
          _message(from: 'alice', body: 'b', sentAtMs: _afterMinutes(1)),
        ]),
        [false, true],
      );
    });

    test('exactly five minutes still continues the block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _base),
          _message(from: 'alice', body: 'b', sentAtMs: _afterMinutes(5)),
        ]),
        [false, true],
      );
    });

    test('a longer gap starts a new block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _base),
          _message(from: 'alice', body: 'b', sentAtMs: _afterMinutes(10)),
        ]),
        [false, false],
      );
    });

    test('another sender starts a new block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _base),
          _message(from: 'bob', body: 'b', sentAtMs: _afterMinutes(1)),
        ]),
        [false, false],
      );
    });

    test('a message with no time starts a new block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: null),
          _message(from: 'alice', body: 'b', sentAtMs: _afterMinutes(1)),
        ]),
        [false, false],
      );
    });

    test('three close together, then one much later', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _base),
          _message(from: 'alice', body: 'b', sentAtMs: _afterMinutes(1)),
          _message(from: 'alice', body: 'c', sentAtMs: _afterMinutes(2)),
          _message(from: 'alice', body: 'd', sentAtMs: _afterMinutes(10)),
        ]),
        [false, true, true, false],
      );
    });

    test('a message sent before the one above it starts a new block', () {
      expect(
        _groupedFlags([
          _message(from: 'alice', body: 'a', sentAtMs: _afterMinutes(2)),
          _message(from: 'alice', body: 'b', sentAtMs: _base),
        ]),
        [false, false],
      );
    });
  });

  for (final testCase in conversationCases()) {
    testWidgets('${testCase.label}: two grouped messages show one sender meta',
        (tester) async {
      await pumpConversation(
        tester,
        testCase,
        messages: [
          TestMessage(body: 'first', sentAtMs: _base),
          TestMessage(body: 'second', sentAtMs: _afterMinutes(1)),
        ],
      );

      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);

      // The sender name shows once, not once per row. Scoped to the rows,
      // because a DM also shows the peer name in its header.
      expect(
        find.descendant(
          of: find.byType(ConversationMessageRow),
          matching: find.text('peer'),
        ),
        findsOneWidget,
      );

      // The clock is local and locale-aware, so build the expectation the
      // same way the row does instead of hard-coding a time.
      final clock = DateFormat.Hm('en').format(
        DateTime.fromMillisecondsSinceEpoch(_base.toInt()).toLocal(),
      );
      expect(find.text(clock), findsOneWidget);
    });
  }
}
