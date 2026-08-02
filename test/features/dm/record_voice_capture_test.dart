// Unit tests for the pure, mic-free parts of `RecordVoiceCaptureFactory`:
// the PCM16 stream framer (`PcmFrameBuffer`). The real `record` mic capture and the frb Opus
// encode path need a native mic + the mosh-core cdylib, neither of which is
// present under `flutter test`, so they are device-integration-validated
// separately -- this file covers the logic that can be exercised headless.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/dm/record_voice_capture.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  group('PcmFrameBuffer', () {
    test('emits one frame across three partial chunks and carries the tail',
        () {
      // 1000 then another 1000 -> 2000 bytes, crossing the 1920 boundary so
      // exactly one frame is ready with 80 bytes carried over. Feeding 920
      // more grows the tail to 1000, still under 1920 (partial carry-over).
      final buf = PcmFrameBuffer();
      buf.feed(_bytes(1000));
      expect(buf.hasFrame, isFalse);
      buf.feed(_bytes(1000));
      expect(buf.hasFrame, isTrue); // 2000 >= 1920
      expect(buf.takeFrame().length, kPcmFrameBytes);
      expect(buf.hasFrame, isFalse); // 80 bytes leftover
      buf.feed(_bytes(920));
      expect(buf.hasFrame, isFalse); // 80 + 920 = 1000 < 1920
    });

    test('yields multiple frames from a single oversize chunk', () {
      // 4000 bytes = two 1920 frames + 160 leftover.
      final buf = PcmFrameBuffer()..feed(_bytes(4000));
      expect(buf.takeFrame().length, kPcmFrameBytes);
      expect(buf.takeFrame().length, kPcmFrameBytes);
      expect(buf.hasFrame, isFalse);
    });

    test('empty chunk is a no-op', () {
      final buf = PcmFrameBuffer()..feed(_bytes(0));
      expect(buf.hasFrame, isFalse);
    });

    test('exactly one frame emits and leaves nothing', () {
      final buf = PcmFrameBuffer()..feed(_bytes(kPcmFrameBytes));
      expect(buf.hasFrame, isTrue);
      expect(buf.takeFrame().length, kPcmFrameBytes);
      expect(buf.hasFrame, isFalse);
    });
  });

  test('RecordVoiceCaptureFactory.isSupported is true', () {
    // pcm16bits is universally supported per the record docs; the getter is
    // sync so the honest default is `true`. The real device check happens in
    // `start()` via `hasPermission`.
    expect(const RecordVoiceCaptureFactory().isSupported, isTrue);
  });
}
