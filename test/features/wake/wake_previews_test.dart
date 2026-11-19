import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/wake/wake_previews.dart';
import 'package:mosh/src/rust/conversation/wake/preview.dart';

void main() {
  test(
      'the extension gets each chat\'s name, keys and group members, written '
      'when they change', () async {
    const group = PreviewChat(
        chatId: 'g1',
        name: 'Hikes',
        keys: ['g'],
        members: [PreviewMember(key: 'm', name: 'Cleo')]);
    var chats = [
      const PreviewChat(chatId: 's1', name: 'Alice', keys: ['k2', 'k1']),
      group,
    ];
    final saved = <String>[];
    final previews = WakePreviews(
        read: () async => chats, save: (json) async => saved.add(json));

    await previews.sync();
    await previews.sync();
    chats = [
      const PreviewChat(chatId: 's1', name: 'Alice', keys: ['k3', 'k2']),
      group,
    ];
    await previews.sync();

    const groupJson = {
      'chat': 'g1',
      'name': 'Hikes',
      'keys': ['g'],
      'members': [
        {'key': 'm', 'name': 'Cleo'}
      ]
    };
    expect(saved.map(jsonDecode), [
      [
        {
          'chat': 's1',
          'name': 'Alice',
          'keys': ['k2', 'k1']
        },
        groupJson,
      ],
      [
        {
          'chat': 's1',
          'name': 'Alice',
          'keys': ['k3', 'k2']
        },
        groupJson,
      ],
    ]);
  });

  // The extension keeps the old keys until a write lands.
  test('a write that failed is tried again', () async {
    var fail = true;
    final saved = <String>[];
    final previews = WakePreviews(
        read: () async => [
              const PreviewChat(chatId: 's1', name: 'A', keys: ['k'])
            ],
        save: (json) async {
          if (fail) throw StateError('keychain');
          saved.add(json);
        });

    await expectLater(previews.sync(), throwsStateError);
    fail = false;
    await previews.sync();

    expect(saved, hasLength(1));
  });
}
