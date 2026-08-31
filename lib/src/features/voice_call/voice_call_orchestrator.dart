// VoiceCallOrchestrator -- the audio-transport lifecycle for an active
// 1:1 voice call, 1:1 port of React use-voice-call-orchestration's
// useEffect pump (mosh/src/features/private-dm/voice-call/
// use-voice-call-orchestration.ts L90-200). Riverpod-free + Flutter-free so
// it is unit-testable with Noop capture/playback factories and a recording
// transport.
//
// attach() runs the React effect body: importCallKey -> reset seq/jitter/
// mute -> startVoicePlayback -> startVoiceCapture(onFrame: snapshot+inc
// seq synchronously then sealFrame + transport.sendFrameBytes) -> a 20ms
// Timer.periodic guarded by `draining` that runs drainCallFrames with the
// transport as source + playback as sink + a fresh JitterBuffer.
// detach() is the React cleanup: cancelled=true, cancel timer, stop both
// handles, null the refs, reset seq/mute. A `cancelled` flag gates the two
// await windows (playback/capture resolving after detach) so a teardown
// during setup does not leak or clobber.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;

import 'call_drain.dart' show drainCallFrames;
import 'call_frame_transport.dart' show CallFrameTransport;
import 'frame_codec.dart' show CALLER_DIRECTION_BIT, CALLEE_DIRECTION_BIT;
import 'frame_crypto.dart' show importCallKey, sealFrame;
import 'jitter_buffer.dart' show JitterBuffer;
import 'voice_capture.dart' show VoiceCaptureFactory, VoiceCaptureHandle;
import 'voice_playback.dart' show VoicePlaybackFactory, VoicePlaybackHandle;

// The setup-failure reason passed to endCall when attach throws -- 1:1
// with React's `endCall(sessionId, callId, "setup_failed")`.
const String kSetupFailedReason = 'setup_failed';

// The 20ms frame-poll interval -- 1:1 with React's `CALL_FRAME_POLL_MS`.
const Duration kCallFramePollInterval = Duration(milliseconds: 20);

class VoiceCallOrchestrator {
  VoiceCallOrchestrator();

  SecretKey? _key;
  BigInt _seq = BigInt.zero;
  JitterBuffer? _jitter;
  VoiceCaptureHandle? _capture;
  VoicePlaybackHandle? _playback;
  Timer? _poll;
  bool _cancelled = false;
  bool _draining = false;
  bool _muted = false;

  // Whether the local mic is muted -- 1:1 with React's `callMuted`.
  bool get isMuted => _muted;

  // Toggles mute -- 1:1 with React's `toggleMute`. While muted the
  // capture onFrame early-returns and no frame is sealed/sent.
  void toggleMute() {
    _muted = !_muted;
  }

  // Attaches to an active call and starts the audio-transport loops.
  // Mirrors the React useEffect body. Call detach() to tear down.
  Future<void> attach({
    required String sessionId,
    required String callId,
    required String keyB64,
    required String noncePrefixB64,
    required String direction, // "caller" | "callee"
    required CallFrameTransport transport,
    required VoiceCaptureFactory captureFactory,
    required VoicePlaybackFactory playbackFactory,
    required void Function(String? message) onError,
    required Future<void> Function(String sessionId, String callId, String reason) endCall,
  }) async {
    final directionBit =
        direction == 'caller' ? CALLER_DIRECTION_BIT : CALLEE_DIRECTION_BIT;
    _cancelled = false;
    try {
      final key = await importCallKey(keyB64);
      if (_cancelled) return;
      _key = key;
      _seq = BigInt.zero;
      _muted = false;
      _jitter = JitterBuffer();
      final playback = await playbackFactory.start();
      if (_cancelled) {
        await playback.stop();
        return;
      }
      _playback = playback;
      final capture = await captureFactory.start((frame) {
        if (_cancelled || _muted) return;
        final key = _key;
        if (key == null) return;
        // Snapshot+increment synchronously: sealFrame is async, so two
        // frames in flight would otherwise reuse the AES-GCM nonce.
        final seq = _seq;
        _seq = _seq + BigInt.one;
        _sealAndSend(
          key: key,
          noncePrefix: noncePrefixB64,
          seq: seq,
          directionBit: directionBit,
          frame: frame,
          transport: transport,
          sessionId: sessionId,
          callId: callId,
        );
      });
      if (_cancelled) {
        await capture.stop();
        return;
      }
      _capture = capture;
      _poll = Timer.periodic(kCallFramePollInterval, (_) {
        final key = _key;
        final jitter = _jitter;
        final playback = _playback;
        if (_draining || key == null || jitter == null || playback == null) {
          return;
        }
        _draining = true;
        // 1:1 with React's `.catch(...).finally(...)`: swallow poll errors
        // and always reset the draining guard so the next tick can fire.
        drainCallFrames(
          source: transport,
          sessionId: sessionId,
          callId: callId,
          key: key,
          noncePrefix: noncePrefixB64,
          jitter: jitter,
          playback: playback,
        ).then((_) {}, onError: (_) {}).whenComplete(() {
          _draining = false;
        });
      });
    } catch (err) {
      onError(err is Exception ? err.toString() : 'Voice call setup failed');
      await endCall(sessionId, callId, kSetupFailedReason);
    }
  }

  // Detaches from the active call and tears down all resources -- 1:1
  // with the React useEffect cleanup. Idempotent: safe to call when not
  // attached or after a partial attach.
  Future<void> detach() async {
    _cancelled = true;
    _poll?.cancel();
    _poll = null;
    final capture = _capture;
    final playback = _playback;
    _capture = null;
    _playback = null;
    _key = null;
    _seq = BigInt.zero;
    _jitter = null;
    _muted = false;
    if (capture != null) {
      try {
        await capture.stop();
      } catch (_) {}
    }
    if (playback != null) {
      try {
        await playback.stop();
      } catch (_) {}
    }
  }

  // Seals + sends one captured frame. Fire-and-forget; the capture onFrame
  // already snapshotted+incremented seq synchronously.
  Future<void> _sealAndSend({
    required SecretKey key,
    required String noncePrefix,
    required BigInt seq,
    required BigInt directionBit,
    required Uint8List frame,
    required CallFrameTransport transport,
    required String sessionId,
    required String callId,
  }) async {
    try {
      final seal = await sealFrame(key, noncePrefix, seq, directionBit, frame);
      await transport.sendFrameBytes(sessionId, callId, seal);
    } catch (_) {
      // React: console.warn("[voice-call] send failed", err) -- swallow here.
    }
  }
}
