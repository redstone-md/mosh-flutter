// CpalVoicePlaybackFactory -- the real playback pipeline behind the
// VoicePlaybackFactory seam. 1-1 with React's `audio-playback.ts`: mosh-core's
// frb-exposed `voice_call_playback` decodes Opus via
// `audiopus::coder::Decoder` and plays via a `cpal::Stream` fed from a ring
// buffer with drift-resync (`PLAYBACK_RESYNC_S = 0.2s`). Dart is a thin
// wrapper over the frb opaque -- the real work (decode, ring, resync) is in
// Rust.
//
// Since `VoicePlaybackHandle implements CallFrameSink` (voice_playback.dart),
// the handle returned here is passable straight into `drainCallFrames(...,
// playback: handle)` -- no adapter, exactly like React's
// `playbackRef.current = startVoicePlayback()`.

library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mosh/src/rust/api/voice_call_playback.dart'
    show VoicePlayback, voiceCallPlaybackStart, voiceCallPlaybackStop;
import 'package:mosh/src/rust/api/voice_call_playback.dart'
    show voiceCallPlaybackPushFrame;

import 'voice_playback.dart';

/// [VoicePlaybackFactory] backed by mosh-core's `voice_call_playback`
/// (audiopus decode + cpal output + ring buffer). Constructed at runtime
/// where a speaker is present; tests use [NoopVoicePlaybackFactory]. There is
/// no `isSupported` getter on the seam (React's `startVoicePlayback()` has no
/// analog to capture's `isCallAudioSupported()`), so `start()` just opens the
/// device and throws synchronously if none is available.
class CpalVoicePlaybackFactory implements VoicePlaybackFactory {
  const CpalVoicePlaybackFactory();

  @override
  Future<VoicePlaybackHandle> start() async {
    // `voiceCallPlaybackStart` is `#[frb(sync)]`: it returns the opaque
    // directly and throws a Dart exception on failure (no default device,
    // stream build/play error). `start()` stays `Future`-typed for the seam;
    // no async I/O is actually needed, so the future completes immediately.
    final VoicePlayback inner = voiceCallPlaybackStart();
    return _CpalVoicePlaybackHandle(inner);
  }
}

/// [VoicePlaybackHandle] for [CpalVoicePlaybackFactory]: a thin owner of the
/// frb `VoicePlayback` opaque. `pushFrame` decodes + enqueues one Opus packet
/// (the Rust side does the decode + ring push + drift-resync); `stop` drops
/// the cpal stream (Rust mirrors React's `context.close()`). Both frb calls
/// are `#[frb(sync)]` and throw on failure -- the `_stopped` guard makes
/// `stop()` idempotent and `pushFrame` after `stop` a no-op, matching the
/// seam's "inert if already stopped" contract.
class _CpalVoicePlaybackHandle implements VoicePlaybackHandle {
  _CpalVoicePlaybackHandle(this._inner);

  final VoicePlayback _inner;
  bool _stopped = false;

  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {
    if (_stopped) return;
    voiceCallPlaybackPushFrame(p: _inner, seq: seq, opus: opusFrame);
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    voiceCallPlaybackStop(p: _inner);
  }
}
