import 'call_dialog.dart';
import 'ringtone_player.dart';

/// The ringtone belongs to the call, not its window. mosh-core ends an
/// unanswered call itself; the ringtone stops when the call leaves the
/// snapshot.
class CallRinging {
  CallRinging(this.player, {this.incomingManaged = false});

  final RingtonePlayer player;
  final bool incomingManaged;
  RingtoneHandle? _handle;
  String? _callId;

  void update(CallDialog dialog, {required bool busy}) {
    if (incomingManaged && dialog is IncomingCallDialog) {
      dispose();
      return;
    }
    if (dialog is IncomingCallDialog && dialog.pending.answerPending) {
      dispose();
      return;
    }
    if (dialog is! IncomingCallDialog && dialog is! OutgoingCallDialog) {
      dispose();
      return;
    }
    if (_callId != dialog.callId) {
      dispose();
      _callId = dialog.callId;
    }
    if (busy) {
      stop();
      return;
    }
    if (_handle == null) {
      try {
        _handle = player.start(dialog is IncomingCallDialog
            ? RingtoneKind.incoming
            : RingtoneKind.outgoing);
      } catch (_) {
        // Call controls remain usable when the output device is unavailable.
      }
    }
  }

  void stop() {
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
  }
}
