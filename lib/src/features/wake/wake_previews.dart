import 'dart:convert';

import 'package:mosh/src/rust/private_dm_runtime/wake_preview.dart';

/// Keeps this iPhone's notification extension able to show a woken chat's
/// name and text: hands it each chat's name and preview keys
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
          {'session': chat.sessionId, 'name': chat.name, 'keys': chat.keys},
      ]);
      if (chats == _saved) return;
      await save(chats);
      _saved = chats;
    } finally {
      _running = false;
    }
  }
}
