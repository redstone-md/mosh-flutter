// VoicePlayback -- the seam between the call orchestrator and an actual
// audio playback pipeline. React's `audio-playback.ts` schedules decoded
// Opus frames via Web Audio with drift-resync. Flutter's real playback
// (the `media_kit` package) is a later slice; to keep the orchestrator
// unit-testable without a native audio backend, the orchestrator takes a
// [VoicePlaybackFactory] and calls `start()` to get a [VoicePlaybackHandle]
// it feeds via `pushFrame` and `stop()`s on detach -- exactly mirroring
// React's `playbackRef.current = startVoicePlayback()` /
// `playbackRef.current.pushFrame(seq, payload)` / `playbackRef.current
// ?.stop()` lifecycle.
//
// Note: [VoicePlaybackHandle.pushFrame] is signature-identical to
// [CallFrameSink.pushFrame] (call_drain.dart), so the orchestrator passes
// the playback handle straight into [drainCallFrames] as the sink -- no
// adapter needed.
//
// Dart interfaces are nominal, not structural, so the orchestrator can
// only pass a [VoicePlaybackHandle]-typed value where a [CallFrameSink]
// is expected if [VoicePlaybackHandle] itself declares `implements
// CallFrameSink` (the factory returns [VoicePlaybackHandle], not the
// private [_NoopHandle]). The lint ignore below reconciles the inevitable
// parameter-name divergence between [VoicePlaybackHandle] (`opusFrame`)
// and [CallFrameSink] (`payload`) -- the method signature is identical,
// only the parameter name differs.
// ignore_for_file: avoid_renaming_method_parameters
library;

import 'dart:typed_data';

import 'call_drain.dart';

/// A handle to a started voice playback -- mirrors React's
/// `VoicePlaybackHandle` (`{ pushFrame(seq, payload); stop(): void }`).
/// The orchestrator holds this from `start()` until `detach()`, feeds
/// it decoded frames via `pushFrame`, then calls `stop()`. Implements
/// [CallFrameSink] so the orchestrator can pass it straight into
/// [drainCallFrames] as the playback sink with no adapter.
abstract interface class VoicePlaybackHandle implements CallFrameSink {
  /// Schedules a decoded frame for playback. Signature-identical to
  /// [CallFrameSink.pushFrame]; the parameter is named `opusFrame` here
  /// to mirror the React source's semantic, while [CallFrameSink] names
  /// it `payload` -- the signatures match, only the name differs.
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
