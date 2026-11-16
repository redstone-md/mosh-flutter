import 'call_dialog.dart';

/// What the system call screen shows a call as.
enum SystemCallKind { incoming, outgoing, active }

/// What the user did on the system call screen.
final class SystemCallAction {
  const SystemCallAction.answer(this.callId)
      : kind = SystemCallActionKind.answer,
        muted = false;
  const SystemCallAction.end(this.callId)
      : kind = SystemCallActionKind.end,
        muted = false;
  const SystemCallAction.mute(this.callId, {required this.muted})
      : kind = SystemCallActionKind.mute;

  final String callId;
  final SystemCallActionKind kind;
  final bool muted;
}

enum SystemCallActionKind { answer, end, mute }

/// The phone's own call screen (CallKit on iPhone,
/// `ios/Runner/SystemCalls.swift`): it rings, shows and ends calls, and
/// reports what the user does there.
abstract interface class SystemCallScreen {
  Future<void> show(String callId, SystemCallKind kind, String name);
  Future<void> ended(String callId);
  set onAction(void Function(SystemCallAction action)? handler);
}

/// Mirrors the app's one call onto the system call screen and carries the
/// user's actions there back to the call. A push can ring the phone before
/// Moss has delivered the offer, so an answer or decline for a call the app
/// does not know yet waits for it.
class SystemCallMirror {
  SystemCallMirror(this._screen,
      {required this.answer, required this.end, required this.mute});

  final SystemCallScreen _screen;
  final Future<void> Function(String callId) answer;
  final Future<void> Function(String callId) end;
  final void Function(String callId, bool muted) mute;

  (String, SystemCallKind, String)? _shown;
  final _early = <String, SystemCallActionKind>{};

  void show(CallDialog dialog) {
    final previous = _shown;
    if (previous != null && previous.$1 != dialog.callId) {
      _shown = null;
      _screen.ended(previous.$1);
    }
    final kind = switch (dialog) {
      IncomingCallDialog() => SystemCallKind.incoming,
      OutgoingCallDialog() => SystemCallKind.outgoing,
      ActiveCallDialog() => SystemCallKind.active,
      NoCallDialog() => null,
    };
    if (kind == null) return;
    final next = (dialog.callId, kind, dialog.peerName);
    if (next == _shown) return;
    _shown = next;
    _screen.show(dialog.callId, kind, dialog.peerName);
    if (kind == SystemCallKind.incoming) {
      switch (_early.remove(dialog.callId)) {
        case SystemCallActionKind.answer:
          answer(dialog.callId);
        case SystemCallActionKind.end:
          end(dialog.callId);
        case SystemCallActionKind.mute || null:
          break;
      }
    }
  }

  void act(SystemCallAction action) {
    if (_shown?.$1 != action.callId) {
      if (action.kind != SystemCallActionKind.mute) {
        _early[action.callId] = action.kind;
      }
      return;
    }
    switch (action.kind) {
      case SystemCallActionKind.answer:
        answer(action.callId);
      case SystemCallActionKind.end:
        end(action.callId);
      case SystemCallActionKind.mute:
        mute(action.callId, action.muted);
    }
  }
}
