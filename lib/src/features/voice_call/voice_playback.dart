import 'dart:typed_data';

import 'call_drain.dart';

/// A handle to a started voice playback. The orchestrator holds this from
/// `start()` until `detach()`, feeds it decoded frames via `pushFrame`, then
/// calls `stop()`. Implements
/// [CallFrameSink] so the orchestrator can pass it straight into
/// [drainCallFrames] as the playback sink with no adapter.
abstract interface class VoicePlaybackHandle implements CallFrameSink {
  /// Schedules a decoded frame for playback. Signature-identical to
  /// [CallFrameSink.pushFrame]; only the parameter name differs.
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame);

  /// Stops the playback pipeline. Inert if already stopped.
  Future<void> stop();
}

/// The factory seam the orchestrator calls. `start()` returns a
/// [VoicePlaybackHandle] the orchestrator feeds + `stop()`s.
abstract interface class VoicePlaybackFactory {
  Future<VoicePlaybackHandle> start();
}

/// A [VoicePlaybackHandle] whose `pushFrame`/`stop` are inert --
/// returned by [NoopVoicePlaybackFactory] so the orchestrator's feed
/// and `stop()` are always safe and produce no sound. Declares
/// `implements [CallFrameSink]` explicitly (in addition to inheriting it
/// via [VoicePlaybackHandle]) to document that a started handle is
/// usable as a [CallFrameSink] for [drainCallFrames] with no adapter.
class _NoopHandle implements VoicePlaybackHandle, CallFrameSink {
  const _NoopHandle();
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {}
  @override
  Future<void> stop() async {}
}

/// Default [VoicePlaybackFactory]: starts nothing, returns an inert
/// handle. Used by tests + as the fallback before the real
/// `media_kit`-backed playback lands.
class NoopVoicePlaybackFactory implements VoicePlaybackFactory {
  const NoopVoicePlaybackFactory();
  @override
  Future<VoicePlaybackHandle> start() async => const _NoopHandle();
}
