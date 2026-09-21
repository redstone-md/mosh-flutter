// RecordVoiceCaptureFactory -- the real mic capture pipeline behind the
// VoiceCaptureFactory seam. Captures 48 kHz mono PCM16 via the `record`
// package (`AudioEncoder.pcm16bits` is universal -- record's native Opus
// encoder is Android/iOS/Linux only, so the Opus encode happens in Rust
// via mosh-core's `voice_call_opus_encode`), buffers each 20 ms frame
// (1920 bytes = 960 i16 samples), encodes it to an Opus packet, and emits
// the packet via `onFrame`. `echoCancel` / `noiseSuppress` / `autoGain`
// request the platform's voice-processing DSP.
//
// The pure helper (`PcmFrameBuffer`) is exposed
// public so the framing logic is unit-testable
// without the native mic or the frb cdylib (neither is present under
// `flutter test`); the real encode path is device-integration-validated
// separately.

library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mosh/src/rust/api/voice_call_opus_encode.dart'
    show VoiceCallOpusEncoder, voiceCallOpusEncode, voiceCallOpusEncoderNew;
import 'package:record/record.dart'
    show AudioEncoder, AudioRecorder, RecordConfig;

import 'voice_capture.dart';

/// The 20 ms frame size at 48 kHz mono PCM16: 960 samples * 2 bytes (int16 LE).
const int kPcmFrameBytes = 1920;

/// A pure framer that accumulates arbitrary PCM16 stream chunks and yields
/// complete 1920-byte (960-sample) frames. Exposed `@visibleForTesting` so the
/// framing edge cases (partial chunks, multi-frame chunks, empty input) are
/// unit-testable without the mic. `takeFrame` is only valid right after a
/// truthy `hasFrame()`. Internal buffer is a growable `List<int>` because a
/// `Uint8List` is fixed-length and cannot absorb appended chunks in place.
class PcmFrameBuffer {
  final List<int> _pending = <int>[];
  void feed(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _pending.addAll(chunk);
  }

  bool get hasFrame => _pending.length >= kPcmFrameBytes;
  Uint8List takeFrame() {
    final frame = Uint8List.fromList(_pending.sublist(0, kPcmFrameBytes));
    _pending.removeRange(0, kPcmFrameBytes);
    return frame;
  }
}

/// [VoiceCaptureFactory] backed by `record` + mosh-core Opus. Constructed at
/// runtime where a mic is present; tests use [NoopVoiceCaptureFactory].
class RecordVoiceCaptureFactory implements VoiceCaptureFactory {
  const RecordVoiceCaptureFactory();

  // `AudioEncoder.pcm16bits` is universally supported per the `record` docs
  // (desktop + mobile). `isSupported` is a sync getter, so the honest default
  // is `true`; the real device check happens in `start()` via `hasPermission`.
  @override
  bool get isSupported => true;

  @override
  Future<VoiceCaptureHandle> start(
      void Function(Uint8List opusFrame) onFrame) async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      throw StateError('microphone permission denied');
    }
    final VoiceCallOpusEncoder encoder = voiceCallOpusEncoderNew();
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 48000,
      numChannels: 1,
      bitRate:
          256000, // pcm16 ignores bitRate; record requires a non-zero value
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
    );
    final stream = await recorder.startStream(config);
    final buffer = PcmFrameBuffer();
    final sub = stream.listen((chunk) {
      buffer.feed(Uint8List.fromList(chunk));
      while (buffer.hasFrame) {
        final Uint8List opus = voiceCallOpusEncode(
          encoder: encoder,
          pcm16: buffer.takeFrame(),
        );
        // Emit every encoder packet, including DTX comfort-noise (1-3 byte
        // silence packets) -- forwarding all chunks unfiltered keeps the
        // encoder's DTX signaling intact.
        onFrame(opus);
      }
    });
    // The encoder is captured by the `sub.listen` closure, so it stays alive
    // for the subscription's lifetime; the handle only needs the recorder +
    // subscription to tear the stream down.
    return _RecordVoiceCaptureHandle(recorder, sub);
  }
}

/// [VoiceCaptureHandle] for [RecordVoiceCaptureFactory]: cancels the stream
/// subscription (which drops the encoder captured in its `.listen` closure)
/// and stops + disposes the recorder.
class _RecordVoiceCaptureHandle implements VoiceCaptureHandle {
  _RecordVoiceCaptureHandle(this._recorder, this._sub);
  final AudioRecorder _recorder;
  final StreamSubscription<Uint8List> _sub;
  bool _stopped = false;

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sub.cancel();
    await _recorder.stop();
    await _recorder.dispose();
  }
}
