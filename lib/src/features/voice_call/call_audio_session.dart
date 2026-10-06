import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:mosh/src/gateway/bridge_facade.dart';

import 'call_drain.dart';
import 'frame_codec.dart';
import 'frame_crypto.dart';
import 'jitter_buffer.dart';
import 'voice_capture.dart';
import 'voice_playback.dart';

/// One audio lifetime. Cancellation invalidates pending work immediately;
/// startup releases any handles that arrive after cancellation.
class CallAudioSession {
  CallAudioSession({
    required this.sessionId,
    required this.callId,
    required this.keyB64,
    required this.noncePrefix,
    required this.direction,
    required this.bridge,
    required this.captureFactory,
    required this.playbackFactory,
  });

  final String sessionId;
  final String callId;
  final String keyB64;
  final String noncePrefix;
  final String direction;
  final BridgeFacade bridge;
  final VoiceCaptureFactory captureFactory;
  final VoicePlaybackFactory playbackFactory;
  final JitterBuffer _jitter = JitterBuffer();
  SecretKey? _key;
  VoiceCaptureHandle? _capture;
  VoicePlaybackHandle? _playback;
  Timer? _poll;
  BigInt _seq = BigInt.zero;
  bool _cancelled = false;
  bool _draining = false;
  bool muted = false;

  bool get ready => !_cancelled && _capture != null && _playback != null;

  Future<void> start() async {
    _key = await importCallKey(keyB64);
    if (_cancelled) return;
    final playback = await playbackFactory.start();
    if (_cancelled) {
      await playback.stop();
      return;
    }
    _playback = playback;
    final capture = await captureFactory.start(_onFrame);
    if (_cancelled) {
      await capture.stop();
      return;
    }
    _capture = capture;
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) => _drain());
  }

  void _onFrame(Uint8List frame) {
    if (_cancelled || muted) return;
    final key = _key;
    if (key == null) return;
    final seq = _seq;
    _seq += BigInt.one;
    unawaited(_send(key, seq, frame));
  }

  Future<void> _send(SecretKey key, BigInt seq, Uint8List frame) async {
    try {
      final directionBit =
          direction == 'caller' ? CALLER_DIRECTION_BIT : CALLEE_DIRECTION_BIT;
      final wire = await sealFrame(key, noncePrefix, seq, directionBit, frame);
      if (!_cancelled) {
        await bridge.callSendFrame(
            sessionId: sessionId, callId: callId, frame: wire);
      }
    } catch (_) {
      // Individual media packets may be lost without ending a call.
    }
  }

  Future<void> _drain() async {
    final playback = _playback;
    final key = _key;
    if (_cancelled || _draining || key == null || playback == null) return;
    _draining = true;
    try {
      await drainCallFrames(
        bridge: bridge,
        sessionId: sessionId,
        callId: callId,
        key: key,
        noncePrefix: noncePrefix,
        jitter: _jitter,
        playback: playback,
        isCurrent: () => !_cancelled,
      );
    } catch (_) {
      // A failed drain is retried on the next media tick.
    } finally {
      _draining = false;
    }
  }

  void cancel() {
    _cancelled = true;
    _poll?.cancel();
    _poll = null;
  }

  Future<void> stop() async {
    cancel();
    final capture = _capture;
    final playback = _playback;
    _capture = null;
    _playback = null;
    for (final stop in [capture?.stop, playback?.stop]) {
      if (stop == null) continue;
      try {
        await stop();
      } catch (_) {
        // Release the other resource even if this one refuses teardown.
      }
    }
  }
}
