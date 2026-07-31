import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/util/unread.dart';

List<ConversationCount> counts(List<List<Object>> entries) => entries
    .map((e) => ConversationCount(id: e[0] as String, messageCount: e[1] as int))
    .toList();

void main() {
  group('diffConversations', () {
    test('reports new messages for conversations whose count grew', () {
      final lastSeen = {'a': 2, 'b': 5};
      final result = diffConversations(
        counts([
          ['a', 4],
          ['b', 5],
        ]),
        lastSeen,
        'b',
        false,
      );
      expect(result.newMessages, [NewMessages(id: 'a', delta: 2)]);
    });

    test('does not report the active conversation while the window is focused',
        () {
      final lastSeen = {'a': 1};
      final result = diffConversations(counts([['a', 3]]), lastSeen, 'a', false);
      expect(result.newMessages, isEmpty);
    });

    test('reports the active conversation when the window is unfocused', () {
      final lastSeen = {'a': 1};
      final result = diffConversations(counts([['a', 3]]), lastSeen, 'a', true);
      expect(result.newMessages, [NewMessages(id: 'a', delta: 2)]);
    });

    test('treats a first-seen conversation as having no new messages', () {
      final result = diffConversations(counts([['a', 4]]), <String, int>{}, null, false);
      expect(result.newMessages, isEmpty);
      expect(result.nextLastSeen['a'], 4);
    });

    test('advances lastSeen for every conversation', () {
      final result = diffConversations(
        counts([
          ['a', 7],
          ['b', 2],
        ]),
        {'a': 3},
        null,
        false,
      );
      expect(result.nextLastSeen['a'], 7);
      expect(result.nextLastSeen['b'], 2);
    });
  });

  group('countMessagesFromOthers', () {
    test('ignores messages sent by the local display name', () {
      final count = countMessagesFromOthers(
        [
          MessageAuthor(fromDevice: 'Alice'),
          MessageAuthor(fromDevice: 'Bob'),
          MessageAuthor(fromDevice: 'Alice'),
        ],
        'Alice',
      );

      expect(count, 1);
    });

    test("counts a same-name peer's messages when fingerprints differ", () {
      final count = countMessagesFromOthers(
        [
          MessageAuthor(fromDevice: 'Alice', fromFingerprint: 'AAAA'),
          MessageAuthor(fromDevice: 'Alice', fromFingerprint: 'BBBB'),
        ],
        'Alice',
        'AAAA',
      );

      expect(count, 1);
    });

    test(
        'excludes own messages by fingerprint even after a display-name change',
        () {
      final count = countMessagesFromOthers(
        [
          MessageAuthor(fromDevice: 'OldName', fromFingerprint: 'AAAA'),
          MessageAuthor(fromDevice: 'Bob', fromFingerprint: 'BBBB'),
        ],
        'NewName',
        'AAAA',
      );

      expect(count, 1);
    });
  });

  group('notificationBody', () {
    test('labels channel notifications with the channel name', () {
      expect(notificationBody('channel:general'),
          NotificationBody(title: 'Mosh', body: '#general - new message'));
    });

    test('uses a generic label for dm and group notifications', () {
      expect(notificationBody('dm:abc'),
          NotificationBody(title: 'Mosh', body: 'New message - new message'));
    });
  });
}
