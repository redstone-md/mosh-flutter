
// VoiceCapture -- the seam between the call orchestrator and an actual
// mic capture pipeline. React's `audio-capture.ts` builds an
// AudioWorklet that encodes 48 kHz mono Opus and calls `onFrame` per
// encoded chunk. Flutter's real mic capture (the `record` package)
// is a later slice; to keep the orchestrator unit-testable without a
// native audio backend, the orchestrator takes a [VoiceCaptureFactory]
// and calls `start(onFrame)` to get a [VoiceCaptureHandle] it `stop()`s
// on detach -- exactly mirroring React's `captureRef.current =
// startVoiceCapture(onFrame)` / `captureRef.current?.stop()` lifecycle.
//
// The default [NoopVoiceCaptureFactory] never calls `onFrame`; the real
// impl lands in a later atomic and is injected from the Riverpod wiring.

library;

import 'dart:typed_data';

/// A handle to a started voice capture -- mirrors React's
/// `VoiceCaptureHandle` (`{ stop(): void }`). The orchestrator holds
/// this from `start()` until `detach()`, then calls `stop()`.
abstract interface class VoiceCaptureHandle {
  /// Stops the capture pipeline. Inert if already stopped.
  Future<void> stop();
}

/// The factory seam the orchestrator calls. `start(onFrame)` returns a
/// [VoiceCaptureHandle] whose `onFrame` callback fires for each encoded
/// Opus frame; `isSupported` mirrors React's `isCallAudioSupported()`.
abstract interface class VoiceCaptureFactory {
  /// Whether a real capture backend is available on this platform.
  bool get isSupported;

  /// Starts the capture; `onFrame` fires (on an arbitrary isolate) per
  /// encoded Opus frame. Callers MUST `stop()` the returned handle.
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame);
}

/// A [VoiceCaptureHandle] whose `stop()` is inert -- returned by
/// [NoopVoiceCaptureFactory] so the orchestrator's `stop()` is always
/// safe and never calls `onFrame`.
class _NoopHandle implements VoiceCaptureHandle {
  const _NoopHandle();
  @override
  Future<void> stop() async {}
}

/// Default [VoiceCaptureFactory]: starts nothing, returns an inert
/// handle, and reports `isSupported == false`. Used by tests + as the
/// fallback before the real `record`-backed capture lands.
class NoopVoiceCaptureFactory implements VoiceCaptureFactory {
  const NoopVoiceCaptureFactory();
  @override
  bool get isSupported => false;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) async => const _NoopHandle();
}
