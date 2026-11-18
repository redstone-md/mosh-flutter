import 'dart:async';

import 'call_dialog.dart';

/// What the system call screen shows a call as.
enum SystemCallKind { incoming, outgoing, active }

/// What the user did on the system call screen.
sealed class SystemCallAction {
  const SystemCallAction(this.callId);
  final String callId;
}

final class SystemCallAnswer extends SystemCallAction {
  const SystemCallAnswer(super.callId);
}

final class SystemCallEnd extends SystemCallAction {
  const SystemCallEnd(super.callId);
}

final class SystemCallMute extends SystemCallAction {
  const SystemCallMute(super.callId, {required this.muted});
  final bool muted;
}

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
  final _early = <String, List<SystemCallAction>>{};

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
    final early = _early.remove(dialog.callId) ?? const [];
    final declined = early.whereType<SystemCallEnd>().firstOrNull;
    if (kind == SystemCallKind.incoming && declined != null) {
      // Declined while only the push rang: the offer ends without ringing.
      _apply(declined);
      return;
    }
    final next = (dialog.callId, kind, dialog.peerName);
    if (next == _shown) return;
    _shown = next;
    _screen.show(dialog.callId, kind, dialog.peerName);
    if (kind == SystemCallKind.incoming) early.forEach(_apply);
  }

  void act(SystemCallAction action) {
    if (_shown?.$1 == action.callId) {
      _apply(action);
    } else {
      (_early[action.callId] ??= []).add(action);
    }
  }

  void _apply(SystemCallAction action) {
    switch (action) {
      case SystemCallAnswer(:final callId):
        unawaited(answer(callId));
      case SystemCallEnd(:final callId):
        unawaited(end(callId));
      case SystemCallMute(:final callId, :final muted):
        mute(callId, muted);
    }
  }
}
