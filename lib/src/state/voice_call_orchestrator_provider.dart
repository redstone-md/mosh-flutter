// Voice-call orchestration wiring (ADR 0010/0013) -- the Riverpod mirror of
// React use-voice-call-orchestration's useEffect dep array. The Notifier
// watches activeSessionProvider(sessionId); when the ActiveCall appears,
// changes (callId/key/nonce/direction), or disappears, it detaches the old
// VoiceCallOrchestrator and attaches the new -- threading gatewayProvider
// -> CallFrameTransport, the capture/playback factories, onError -> a
// callError surfacing seam, and endCall -> gateway.callEnd + invalidate
// activeSession. State is {bool muted} only; activeCall/pendingCallSession/
// callSupported stay derived from activeSessionProvider in VoiceCallLayer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/state/session_providers.dart'
    show activeSessionProvider;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show ActiveCall;
import 'package:mosh/src/features/dm/call_frame_transport.dart'
    show CallFrameTransport;
import 'package:mosh/src/features/dm/voice_call_orchestrator.dart'
    show VoiceCallOrchestrator;
import 'package:mosh/src/features/dm/voice_capture.dart'
    show NoopVoiceCaptureFactory, VoiceCaptureFactory;
import 'package:mosh/src/features/dm/voice_playback.dart'
    show NoopVoicePlaybackFactory, VoicePlaybackFactory;

/// The orchestrator state the CallOverlay reads -- just the mute flag.
/// activeCall / pendingCallSession / callSupported are derived from
/// activeSessionProvider by VoiceCallLayer, not duplicated here.
class VoiceCallOrchestratorState {
  const VoiceCallOrchestratorState({this.muted = false});
  final bool muted;
  VoiceCallOrchestratorState copyWith({bool? muted}) =>
      VoiceCallOrchestratorState(muted: muted ?? this.muted);
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

/// A seam for surfacing voice-call errors (React onError). The wiring in
/// step 6 will read this and show a snackbar; tests override with a
/// recording provider. Default is a no-op print (so errors are not lost in
/// prod before the snackbar wiring lands).
final voiceCallErrorSinkProvider = Provider<void Function(String? message)>(
  (ref) => (message) {
    // ignore: avoid_print
    print(message); // replaced by a snackbar in step 6
  },
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
  // The callId the orchestrator is currently attached to (or null when
  // detached). Used to detect a call-id change and re-attach.
  String? _attachedCallId;

  @override
  VoiceCallOrchestratorState build() {
    // Tear down the orchestrator when the provider is disposed (v3 Notifier
    // has no dispose() hook -- register via ref.onDispose in build).
    ref.onDispose(() {
      final o = _orchestrator;
      if (o != null) {
        o.detach(); // fire-and-forget; onDispose is sync.
      }
    });
    final sessionAsync = ref.watch(activeSessionProvider(sessionId));
    final session = sessionAsync.value;
    final activeCall = session?.activeCall;
    // Re-evaluate whenever the ActiveCall identity changes.
    _maybeReattach(activeCall);
    return VoiceCallOrchestratorState(muted: _orchestrator?.isMuted ?? false);
  }

  void _maybeReattach(ActiveCall? activeCall) {
    if (activeCall == null) {
      // No active call -- detach if we were attached.
      final o = _orchestrator;
      if (o != null) {
        o.detach(); // fire-and-forget; build must stay sync.
        _orchestrator = null;
        _attachedCallId = null;
      }
      return;
    }
    if (_attachedCallId == activeCall.callId && _orchestrator != null) {
      // Same call already attached -- nothing to do.
      return;
    }
    // New (or changed) call -- detach the old, attach the new.
    final old = _orchestrator;
    if (old != null) {
      old.detach();
    }
    final orchestrator = VoiceCallOrchestrator();
    _orchestrator = orchestrator;
    _attachedCallId = activeCall.callId;
    final gateway = ref.read(gatewayProvider);
    final transport = CallFrameTransport(gateway);
    final onError = ref.read(voiceCallErrorSinkProvider);
    final sid = sessionId;
    orchestrator.attach(
      sessionId: sid,
      callId: activeCall.callId,
      keyB64: activeCall.keyB64,
      noncePrefixB64: activeCall.noncePrefixB64,
      direction: activeCall.direction,
      transport: transport,
      captureFactory: ref.read(voiceCaptureFactoryProvider),
      playbackFactory: ref.read(voicePlaybackFactoryProvider),
      onError: onError,
      endCall: (s, c, reason) async {
        await gateway.callEnd(sessionId: s, callId: c, reason: reason);
        ref.invalidate(activeSessionProvider(sid));
      },
    );
  }

  /// Toggles mute (React toggleMute). Mirrors the orchestrator's own flag;
  /// bumps state so the CallOverlay re-renders the mic icon.
  void toggleMute() {
    _orchestrator?.toggleMute();
    state = VoiceCallOrchestratorState(muted: _orchestrator?.isMuted ?? false);
  }
}
