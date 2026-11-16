import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/private_dm_runtime/wake.dart';

import 'wake_client.dart';

/// Sends the wakes the DM runtime asks for: a call ringing a contact's
/// iPhone that is away, or texts waiting for it. Runs on every platform, in
/// the app's process; a handle the service no longer knows is dropped.
class WakeSender {
  WakeSender({required this.take, required this.forget, WakeClient? client})
      : _client = client ?? WakeClient();

  final Future<List<WakeRequest>> Function() take;
  final Future<void> Function(String handle) forget;
  final WakeClient _client;
  Timer? _timer;
  bool _sending = false;

  /// Takes what is waiting and sends it, one wake after another.
  Future<void> send() async {
    for (final request in await take()) {
      if (await _client.wake(request) == WakeOutcome.forgotten) {
        await forget(request.handle);
      }
    }
  }

  void start(Duration interval) {
    _timer ??= Timer.periodic(interval, (_) async {
      if (_sending) return;
      _sending = true;
      try {
        await send();
      } on Object {
        // The next tick asks again; a wake lost here is retried by the
        // runtime with the next call or text.
      } finally {
        _sending = false;
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _client.close();
  }
}

/// The process's sender; null where nothing sends wakes (tests).
final wakeSenderProvider = Provider<WakeSender?>((ref) => null);
