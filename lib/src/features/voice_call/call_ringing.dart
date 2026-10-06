import 'dart:async';

import 'call_dialog.dart';
import 'incoming_call_modal.dart';
import 'ringtone_player.dart';

/// Ringtone and no-answer deadline belong to the call, not its window.
class CallRinging {
  CallRinging(this.player, this.onTimeout);

  final RingtonePlayer player;
  final void Function(String callId) onTimeout;
  RingtoneHandle? _handle;
  Timer? _timer;
  String? _callId;
  DateTime? _deadline;
  bool _timedOut = false;

  void update(CallDialog dialog, {required bool busy}) {
    if (dialog is! IncomingCallDialog && dialog is! OutgoingCallDialog) {
      dispose();
      return;
    }
    if (_callId != dialog.callId) {
      dispose();
      _callId = dialog.callId;
      if (dialog is IncomingCallDialog) {
        _deadline = DateTime.now().add(kIncomingNoAnswerTimeout);
      }
    }
    if (busy || _timedOut) {
      stop();
      return;
    }
    if (_handle == null) {
      try {
        _handle = player.start();
      } catch (_) {
        // Call controls remain usable when the output device is unavailable.
      }
    }
    final deadline = _deadline;
    if (deadline != null && _timer == null && !_timedOut) {
      final remaining = deadline.difference(DateTime.now());
      _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        _timedOut = true;
        stop();
        onTimeout(dialog.callId);
      });
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final handle = _handle;
    _handle = null;
    try {
      handle?.stop();
    } catch (_) {
      // Cleanup is best effort; a refused stop must not block call signaling.
    }
  }

  void dispose() {
    stop();
    _callId = null;
    _deadline = null;
    _timedOut = false;
  }
}
