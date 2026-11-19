import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/wake/wake_previews.dart';
import 'package:mosh/src/rust/private_dm_runtime/wake_preview.dart';

void main() {
  test(
      'the extension gets each chat\'s name and keys, written when they change',
      () async {
    var chats = [
      const PreviewChat(sessionId: 's1', name: 'Alice', keys: ['k2', 'k1']),
    ];
    final saved = <String>[];
    final previews = WakePreviews(
        read: () async => chats, save: (json) async => saved.add(json));

    await previews.sync();
    await previews.sync();
    chats = [
      const PreviewChat(sessionId: 's1', name: 'Alice', keys: ['k3', 'k2']),
    ];
    await previews.sync();

    expect(saved.map(jsonDecode), [
      [
        {
          'session': 's1',
          'name': 'Alice',
          'keys': ['k2', 'k1']
        },
      ],
      [
        {
          'session': 's1',
          'name': 'Alice',
          'keys': ['k3', 'k2']
        },
      ],
    ]);
  });

  // The extension keeps the old keys until a write lands.
  test('a write that failed is tried again', () async {
    var fail = true;
    final saved = <String>[];
    final previews = WakePreviews(
        read: () async => [
              const PreviewChat(sessionId: 's1', name: 'A', keys: ['k'])
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
