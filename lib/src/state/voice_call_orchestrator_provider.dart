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
import 'package:mosh/src/features/dm/ringtone_player.dart'
    show NoopRingtonePlayer, RingtonePlayer;

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
final ringtonePlayerProvider = Provider<RingtonePlayer>(
  (ref) => const NoopRingtonePlayer(),
);

/// A seam for surfacing voice-call errors (React onError). DM screens install
/// a local callback that owns their inline ChatError state; isolated provider
/// tests can override this with a recording callback. The default is a no-op
/// because a provider container has no UI owner to which it can report.
final voiceCallErrorSinkProvider = Provider<void Function(String? message)>(
  (ref) => (_) {},
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
  void Function(String? message)? _providerErrorSink;
  void Function(String? message)? _ownerErrorSink;
  Object? _errorSinkOwner;
  // The callId the orchestrator is currently attached to (or null when
  // detached). Used to detect a call-id change and re-attach.
  String? _attachedCallId;

  @override
  VoiceCallOrchestratorState build() {
    _providerErrorSink = ref.read(voiceCallErrorSinkProvider);
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
      onError: _emitError,
      endCall: (s, c, reason) async {
        await gateway.callEnd(sessionId: s, callId: c, reason: reason);
        ref.invalidate(activeSessionProvider(sid));
      },
    );
  }

  /// Installs the owning screen's local error callback. The owner token keeps
  /// an older widget's dispose from clearing a newer widget's callback.
  void setOwnerErrorSink(
    Object owner,
    void Function(String? message) sink,
  ) {
    _errorSinkOwner = owner;
    _ownerErrorSink = sink;
  }

  /// Removes an owner callback only when it still owns this session notifier.
  /// Once cleared, the provider override remains the effective fallback.
  void clearOwnerErrorSink(Object owner) {
    if (!identical(_errorSinkOwner, owner)) return;
    _errorSinkOwner = null;
    _ownerErrorSink = null;
  }

  void _emitError(String? message) {
    (_ownerErrorSink ?? _providerErrorSink)?.call(message);
  }

  /// Toggles mute (React toggleMute). Mirrors the orchestrator's own flag;
  /// bumps state so the CallOverlay re-renders the mic icon.
  void toggleMute() {
    _orchestrator?.toggleMute();
    state = VoiceCallOrchestratorState(muted: _orchestrator?.isMuted ?? false);
  }
}
