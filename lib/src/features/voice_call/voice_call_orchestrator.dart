import 'dart:async';

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'call_audio_session.dart';
import 'voice_capture.dart';
import 'voice_playback.dart';

const String kSetupFailedReason = 'setup_failed';
const Duration kCallFramePollInterval = Duration(milliseconds: 20);

/// Serializes audio replacement. A new call cannot open the microphone or
/// player until the previous startup and teardown have finished.
class VoiceCallOrchestrator {
  Future<void> _transition = Future.value();
  CallAudioSession? _session;
  (String, String)? _requestedCall;
  int _generation = 0;

  bool get isMuted => _session?.muted ?? false;
  bool get isAttached => _session?.ready ?? false;

  void toggleMute() {
    final session = _session;
    if (session?.ready == true) session!.muted = !session.muted;
  }

  Future<void> attach({
    required String sessionId,
    required String callId,
    required String keyB64,
    required String noncePrefixB64,
    required String direction,
    required BridgeFacade bridge,
    required VoiceCaptureFactory captureFactory,
    required VoicePlaybackFactory playbackFactory,
    required void Function(String? message) onError,
    required Future<void> Function(String, String, String) endCall,
    void Function()? onReady,
  }) {
    final generation = ++_generation;
    _requestedCall = (sessionId, callId);
    _session?.cancel();
    final session = CallAudioSession(
      sessionId: sessionId,
      callId: callId,
      keyB64: keyB64,
      noncePrefix: noncePrefixB64,
      direction: direction,
      bridge: bridge,
      captureFactory: captureFactory,
      playbackFactory: playbackFactory,
    );
    return _transition = _transition.then((_) async {
      await _session?.stop();
      _session = null;
      if (generation != _generation) return;
      _session = session;
      await _start(session, generation, onReady, onError, endCall);
    });
  }

  Future<void> _start(
    CallAudioSession session,
    int generation,
    void Function()? onReady,
    void Function(String?) onError,
    Future<void> Function(String, String, String) endCall,
  ) async {
    try {
      await session.start();
      if (generation == _generation && session.ready) onReady?.call();
    } catch (error) {
      await session.stop();
      if (generation != _generation) return;
      onError('Voice call setup failed: $error');
      try {
        await endCall(session.sessionId, session.callId, kSetupFailedReason);
      } catch (_) {
        // Keep the setup error visible even when signaling also fails.
      }
    }
  }

  /// A disposed owner can only detach the call it owned. This prevents its
  /// delayed cleanup from stopping a replacement call in another DM.
  Future<void> detach({(String, String)? call}) {
    if (call != null && call != _requestedCall) return Future.value();
    ++_generation;
    _requestedCall = null;
    _session?.cancel();
    return _transition = _transition.then((_) async {
      await _session?.stop();
      _session = null;
    });
  }
}
