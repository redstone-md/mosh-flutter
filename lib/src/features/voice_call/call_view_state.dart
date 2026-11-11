import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'call_media_view.dart';

enum CallViewPhase { incoming, confirming, outgoing, active }

enum CallViewAction {
  accept,
  decline,
  end,
  mute,
  camera,
  selectInput,
  selectOutput,
  selectCamera,
  openConversation;

  bool get availableWhileBusy => this == end || this == openConversation;
}

/// Display data of one call. Every command identifies the displayed call.
class CallViewState {
  const CallViewState({
    required this.sessionId,
    required this.callId,
    required this.peer,
    required this.phase,
    this.supersededCallId,
    this.startedAtMs = 0,
    this.muted = false,
    this.audioReady = false,
    this.audioFailed = false,
    this.busy = false,
    this.occupancyConflict = false,
    this.error,
    this.media,
  });

  final String sessionId;
  final String callId;
  final String peer;
  final CallViewPhase phase;
  final String? supersededCallId;
  final int startedAtMs;
  final bool muted;
  final bool audioReady;
  final bool audioFailed;
  final bool busy;
  final bool occupancyConflict;
  final String? error;
  final CallMediaView? media;

  static CallViewState? fromDialog(String sessionId, CallDialog dialog,
      {required String fallback,
      required bool muted,
      required bool audioReady,
      bool audioFailed = false,
      required bool busy,
      bool occupancyConflict = false,
      String? error,
      String? peerOverride,
      CallMediaView? media}) {
    if (dialog is NoCallDialog) return null;
    return CallViewState(
      sessionId: sessionId,
      callId: dialog.callId,
      supersededCallId: dialog.supersededCallId,
      peer: peerOverride ??
          (dialog.peerName.isEmpty ? fallback : dialog.peerName),
      phase: switch (dialog) {
        IncomingCallDialog(:final pending) => pending.answerPending
            ? CallViewPhase.confirming
            : CallViewPhase.incoming,
        OutgoingCallDialog() => CallViewPhase.outgoing,
        ActiveCallDialog() => CallViewPhase.active,
        NoCallDialog() => throw StateError('No call'),
      },
      startedAtMs:
          dialog is ActiveCallDialog ? dialog.active.startedAtMs.toInt() : 0,
      muted: muted,
      audioReady: audioReady,
      audioFailed: audioFailed,
      busy: busy,
      occupancyConflict: occupancyConflict,
      error: error,
      media: media,
    );
  }

  CallViewCommand command(CallViewAction action, {String? deviceId}) =>
      CallViewCommand(
          sessionId: sessionId,
          callId: callId,
          action: action,
          deviceId: deviceId);
}

class CallViewCommand {
  const CallViewCommand({
    required this.sessionId,
    required this.callId,
    required this.action,
    this.deviceId,
  });

  final String sessionId;
  final String callId;
  final CallViewAction action;
  final String? deviceId;

  bool matchesCall(String session, String current,
          {String? supersededCallId}) =>
      sessionId == session &&
      (callId == current ||
          action.availableWhileBusy && callId == supersededCallId);
}
