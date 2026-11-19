import 'dart:convert';

import 'package:mosh/src/rust/conversation/wake/preview.dart';

/// Keeps this iPhone's notification extension able to show a woken chat's
/// name and text: hands it each chat's name, preview keys and, for a group,
/// the members whose signed previews it shows
/// (ios/NotificationService/Previews.swift reads this JSON). The runtime
/// replaces a chat's key once a day and announces it at once, so this runs
/// often and writes only what changed.
class WakePreviews {
  WakePreviews({required this.read, required this.save});

  final Future<List<PreviewChat>> Function() read;
  final Future<void> Function(String chats) save;
  String? _saved;
  bool _running = false;

  Future<void> sync() async {
    if (_running) return;
    _running = true;
    try {
      final chats = jsonEncode([
        for (final chat in await read())
          {
            'chat': chat.chatId,
            'name': chat.name,
            'keys': chat.keys,
            if (chat.members case final members?)
              'members': [
                for (final member in members)
                  {'key': member.key, 'name': member.name},
              ],
          },
      ]);
      if (chats == _saved) return;
      await save(chats);
      _saved = chats;
    } finally {
      _running = false;
    }
  }
}
