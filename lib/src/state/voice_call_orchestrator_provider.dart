// Voice-call orchestration wiring (ADR 0010/0013) -- the one home for the
// live-call decisions: which dialog the session asks for (derived from its
// snapshot), whether the mic is muted, and what went wrong. The layer only
// renders what this notifier decides and routes every control action
// (start / accept / decline / hang up / mute) back here, so a ring bug is
// readable in one file instead of six. activeCall / pendingCall /
// callSupported stay derived from activeSessionProvider by VoiceCallLayer.
//
// Call control is a Riverpod family by sessionId; audio transport is
// Riverpod-free and lives in `voice_call_orchestrator.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart'
    show CallDialog, NoCallDialog, callDialogFor;
import 'package:mosh/src/features/voice_call/call_frame_transport.dart'
    show CallFrameTransport;
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart'
    show VoiceCallOrchestrator;
import 'package:mosh/src/features/voice_call/voice_capture.dart'
    show NoopVoiceCaptureFactory, VoiceCaptureFactory;
import 'package:mosh/src/features/voice_call/voice_playback.dart'
    show NoopVoicePlaybackFactory, VoicePlaybackFactory;
import 'package:mosh/src/features/voice_call/ringtone_player.dart'
    show NoopRingtonePlayer, RingtonePlayer;
import 'package:mosh/src/gateway/bridge_facade.dart' show BridgeFacade;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show ActiveCall, SessionSnapshot;
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;

/// Where a call failure came from. The orchestrator owns the failure; the
/// UI only decides how to show it, and that decision is made here.
enum CallErrorSource {
  /// A call-control action (accept / decline / hang up) failed. The call is
  /// otherwise fine, so this is transient feedback (a snack bar).
  callControl,

  /// Bringing up the audio pipeline failed: the call is dead, so the
  /// message lands in the host conversation's error banner.
  audioSetup,
}

/// A failure the call UI must show, and where it belongs. The cause is
/// already classified, so the layer picks the wording from the bridge kind
/// like every other screen.
class CallError {
  const CallError({required this.cause, required this.source});
  final ConversationActionError cause;
  final CallErrorSource source;
}

/// The orchestrator state the call UI reads. Nothing here is owned by the
/// widget that renders it: the dialog comes from the session snapshot, and
/// the mute flag and the error from the orchestrator itself.
class VoiceCallOrchestratorState {
  const VoiceCallOrchestratorState({
    this.dialog = const NoCallDialog(),
    this.muted = false,
    this.error,
  });

  final CallDialog dialog;
  final bool muted;
  final CallError? error;

  VoiceCallOrchestratorState copyWith({
    CallDialog? dialog,
    bool? muted,
    CallError? error,
  }) =>
      VoiceCallOrchestratorState(
        dialog: dialog ?? this.dialog,
        muted: muted ?? this.muted,
        error: error ?? this.error,
      );

  /// A new state with no error -- used after the layer has shown one.
  VoiceCallOrchestratorState copyWithoutError() =>
      VoiceCallOrchestratorState(dialog: dialog, muted: muted);
}

/// The capture/playback factory providers. Noop defaults keep isolated
/// provider containers inert; the production root binds the real record/cpal
/// implementations, while tests can override these with fakes.
final voiceCaptureFactoryProvider = Provider<VoiceCaptureFactory>(
  (ref) => const NoopVoiceCaptureFactory(),
);
final voicePlaybackFactoryProvider = Provider<VoicePlaybackFactory>(
  (ref) => const NoopVoicePlaybackFactory(),
);
final ringtonePlayerProvider = Provider<RingtonePlayer>(
  (ref) => const NoopRingtonePlayer(),
);

/// Family by sessionId. Riverpod v3 passes the family arg to the Notifier's
/// constructor (Notifier.build takes no arg) -- so the class extends plain
/// Notifier and stores the arg in a field. The constructor-fn below
/// receives the arg from NotifierProvider.family's builder.
final voiceCallOrchestratorProvider = NotifierProvider.family<
    VoiceCallOrchestratorNotifier, VoiceCallOrchestratorState, String>(
  VoiceCallOrchestratorNotifier.new,
);

class VoiceCallOrchestratorNotifier
    extends Notifier<VoiceCallOrchestratorState> {
  VoiceCallOrchestratorNotifier(this.sessionId);
  final String sessionId;

  VoiceCallOrchestrator? _orchestrator;
  // The call the orchestrator is currently attached to (or null when
  // detached). Used to detect a call-id change and re-attach.
  String? _attachedCallId;
  // The call a hang-up has already been sent for. A snapshot re-poll can
  // land before the runtime clears the call; without this the second tap
  // (or the re-poll) would end the same call twice. Reset when the call is
  // gone or the hang-up failed, so the action stays retryable.
  String? _endedCallId;
  // The failure the layer has not yet surfaced. Held as a field (not
  // reconstructed from the snapshot) so a re-poll cannot wipe an unshown
  // error; the layer clears it once it has drawn it.
  CallError? _error;

  @override
  VoiceCallOrchestratorState build() {
    // Riverpod runs `onDispose` on every rebuild, not only on disposal. The
    // session is therefore listened to rather than watched: build never
    // re-runs on the 1 s poll, and the detach below fires only when the
    // provider really goes away. (Watching it detached the audio one poll
    // after attach while the call stayed up.)
    ref.onDispose(() {
      _orchestrator?.detach(); // fire-and-forget; onDispose is sync.
      _orchestrator = null;
      _attachedCallId = null;
    });
    ref.listen(activeSessionProvider(sessionId), (_, next) {
      state = _stateFor(next.value);
    });
    return _stateFor(ref.read(activeSessionProvider(sessionId)).value);
  }

  /// Reconciles the audio transport with [session] and derives the state
  /// the call UI reads from it.
  VoiceCallOrchestratorState _stateFor(SessionSnapshot? session) {
    _maybeReattach(session?.activeCall);
    return VoiceCallOrchestratorState(
      dialog: callDialogFor(session),
      muted: _orchestrator?.isMuted ?? false,
      error: _error,
    );
  }

  void _maybeReattach(ActiveCall? activeCall) {
    if (activeCall == null) {
      final o = _orchestrator;
      if (o != null) {
        o.detach();
        _orchestrator = null;
        _attachedCallId = null;
      }
      _endedCallId = null;
      return;
    }
    if (_attachedCallId == activeCall.callId && _orchestrator != null) {
      return; // same call already attached -- nothing to do.
    }
    _orchestrator?.detach();
    _orchestrator = VoiceCallOrchestrator();
    _attachedCallId = activeCall.callId;
    _endedCallId = null;
    final orchestrator = _orchestrator!;
    final sid = sessionId;
    final bridge = ref.read(bridgeFacadeProvider);
    final transport = CallFrameTransport(bridge);
    orchestrator.attach(
      sessionId: sid,
      callId: activeCall.callId,
      keyB64: activeCall.keyB64,
      noncePrefixB64: activeCall.noncePrefixB64,
      direction: activeCall.direction,
      transport: transport,
      captureFactory: ref.read(voiceCaptureFactoryProvider),
      playbackFactory: ref.read(voicePlaybackFactoryProvider),
      onError: (message) => _fail(message, CallErrorSource.audioSetup),
      endCall: (s, c, reason) async {
        if (!ref.mounted) return;
        await bridge.callEnd(sessionId: s, callId: c, reason: reason);
        ref.invalidate(activeSessionProvider(sid));
      },
    );
  }

  /// Places a call. Resolves to the error to surface, or to null when the
  /// call went out. Not routed through [CallError]: a call that never
  /// started has no layer to surface it, so the caller keeps the error.
  Future<Object?> startCall() async {
    try {
      await ref.read(bridgeFacadeProvider).callStart(sessionId: sessionId);
      if (ref.mounted) ref.invalidate(activeSessionProvider(sessionId));
      return null;
    } catch (e) {
      return e;
    }
  }

  /// Accepts the inbound call [callId] and refreshes the session.
  Future<void> acceptCall(String callId) =>
      _control((b) => b.callAccept(sessionId: sessionId, callId: callId));

  /// Declines the inbound call [callId] for [reason] and refreshes.
  Future<void> declineCall(String callId, String reason) => _control(
        (b) =>
            b.callDecline(sessionId: sessionId, callId: callId, reason: reason),
      );

  /// Hangs up the active call [callId] for [reason] and refreshes. A second
  /// call for the same [callId] before the first clears is a no-op; a failed
  /// hang-up lets a retry through.
  Future<void> endCall(String callId, String reason) async {
    if (_endedCallId == callId) return;
    _endedCallId = callId;
    final ended = await _control(
      (b) => b.callEnd(sessionId: sessionId, callId: callId, reason: reason),
    );
    if (!ended && _endedCallId == callId) _endedCallId = null;
  }

  /// Toggles mute (React toggleMute). Mirrors the orchestrator's own flag;
  /// bumps state so the CallOverlay re-renders the mic icon.
  void toggleMute() {
    _orchestrator?.toggleMute();
    if (ref.mounted) {
      state = state.copyWith(muted: _orchestrator?.isMuted ?? false);
    }
  }

  /// Clears the surfaced error once the layer has shown it.
  void clearError() {
    if (_error == null) return;
    _error = null;
    if (ref.mounted) state = state.copyWithoutError();
  }

  Future<bool> _control(
    Future<void> Function(BridgeFacade bridge) action,
  ) async {
    try {
      await action(ref.read(bridgeFacadeProvider));
      if (ref.mounted) ref.invalidate(activeSessionProvider(sessionId));
      return true;
    } catch (e) {
      _fail(e, CallErrorSource.callControl);
      return false;
    }
  }

  void _fail(Object? error, CallErrorSource source) {
    if (!ref.mounted) return;
    _error = CallError(
      cause: error == null
          ? const ConversationActionError.text('Call failed')
          : ConversationActionError.of(error),
      source: source,
    );
    state = state.copyWith(error: _error);
  }
}
