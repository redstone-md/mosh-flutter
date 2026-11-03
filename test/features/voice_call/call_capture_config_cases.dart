// The call-capture RecordConfig builder regression (macOS 0.9.3 field
// bug: the callee's mic is silent in calls — the caller hears nothing).
//
// Root cause: `RecordVoiceCaptureFactory` asked `record` for
// `echoCancel/autoGain/noiseSuppress: true`, which on macOS maps to
// `AVAudioEngine` + `setVoiceProcessingEnabled(true)` on an input-only
// graph — Apple's VoiceProcessingIO is duplex and, wired one-sided, is a
// documented silent-tap failure mode (Quill RCA-001; SO 59992239): the
// tap delivers zero-filled buffers on some devices/routes. Raw capture
// (all three knobs off) never touches VP.
//
// What is pinned here:
//  1. On macOS the call-capture config requests NO voice processing.
//  2. On other platforms the knobs stay on (the DSP is fine there —
//     unchanged behavior is the safe default).
//  3. The stream config keeps the 48 kHz mono PCM16 shape the Opus encode
//     pipeline depends on.
//
// Pure-config test: no channel, no recorder — the builder is the seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/record_voice_capture.dart';
import 'package:record/record.dart' show AudioEncoder, InputDevice;

void main() {
  test('macOS asks for raw capture: no echo cancel / AGC / noise suppress', () {
    final config = callCaptureRecordConfig(isMacOS: true);
    expect(config.echoCancel, isFalse,
        reason: 'VP-duplex silent-tap bug class on macOS');
    expect(config.autoGain, isFalse);
    expect(config.noiseSuppress, isFalse);
    expect(config.device, isNull, reason: 'no pick stored -> default mic');
  });

  test('non-macOS platforms keep the voice-processing DSP on', () {
    final config = callCaptureRecordConfig(isMacOS: false);
    expect(config.echoCancel, isTrue);
    expect(config.autoGain, isTrue);
    expect(config.noiseSuppress, isTrue);
  });

  test('the PCM16 48 kHz mono shape is unchanged (Opus framing contract)', () {
    final config = callCaptureRecordConfig(isMacOS: true);
    expect(config.encoder, AudioEncoder.pcm16bits);
    expect(config.sampleRate, 48000);
    expect(config.numChannels, 1);
  });

  test('a stored input pick rides the config through to `record`', () {
    final config = callCaptureRecordConfig(
      isMacOS: false,
      inputDevice: const InputDevice(id: 'avcapture:USB Mic', label: 'USB Mic'),
    );
    expect(config.device?.id, 'avcapture:USB Mic');
  });
}
