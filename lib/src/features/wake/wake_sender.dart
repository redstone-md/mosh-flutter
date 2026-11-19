import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/private_dm_runtime/wake.dart';

import 'wake_client.dart';

/// Sends the wakes the DM runtime asks for: a call ringing a contact's
/// iPhone that is away, or texts waiting for it. Runs on every platform, in
/// the app's process. A handle the service no longer knows for calls is
/// dropped; a phone may lack only the alert token texts use. A texts wake
/// refused on every try hands its texts back for the next one.
/// The runtime asks only for wakes through the build's own service.
class WakeSender {
  WakeSender(
      {required this.take,
      required this.forget,
      required this.refused,
      WakeClient? client})
      : _client = client ?? WakeClient();

  final Future<List<WakeRequest>> Function() take;
  final Future<void> Function(String handle) forget;
  final Future<void> Function(String handle) refused;
  final WakeClient _client;
  // Refused wakes and the tries each has left: the runtime asks for a wake
  // once, so a service that was briefly unreachable must be asked again.
  final _retry = <WakeRequest, int>{};
  Timer? _timer;
  bool _sending = false;

  /// Takes what is waiting, with the wakes refused before, and sends it,
  /// one wake after another.
  Future<void> send() async {
    for (final request in {..._retry.keys, ...await take()}) {
      final outcome = await _client.wake(request);
      debugPrint(
          'wake ${request.callId == null ? 'message' : 'call'}: ${outcome.name}');
      final left = (_retry.remove(request) ?? _tries) - 1;
      if (outcome == WakeOutcome.refused && left > 0) _retry[request] = left;
      if (outcome == WakeOutcome.refused &&
          left == 0 &&
          request.callId == null) {
        await refused(request.handle);
      }
      if (outcome == WakeOutcome.forgotten && request.callId != null) {
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

/// How often a refused wake is sent: once a round for a few seconds.
const _tries = 5;

/// The process's sender; null where nothing sends wakes (tests).
final wakeSenderProvider = Provider<WakeSender?>((ref) => null);
