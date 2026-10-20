import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ringtone_player.dart';

/// Android uses ringtone/call volume, rather than CPAL's media-volume stream.
class AndroidRingtonePlayer implements RingtonePlayer {
  const AndroidRingtonePlayer();
  static const channel = MethodChannel('app.mosh/call-ringtone');
  static int _nextId = 0;

  @override
  RingtoneHandle start(RingtoneKind kind) {
    final id = ++_nextId;
    unawaited(_invoke('start', {'id': id, 'kind': kind.name}));
    return _AndroidRingtoneHandle(id);
  }

  static Future<void> _invoke(String method, Map<String, Object> args) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } catch (error) {
      debugPrint('Android ringtone $method failed: ${error.runtimeType}');
    }
  }
}

class _AndroidRingtoneHandle implements RingtoneHandle {
  _AndroidRingtoneHandle(this.id);
  final int id;
  bool _stopped = false;

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    unawaited(AndroidRingtonePlayer._invoke('stop', {'id': id}));
  }
}
