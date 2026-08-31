// Tests for `voice_capture` (lib/src/features/dm/voice_capture.dart) --
// the NoopVoiceCaptureFactory fake + the VoiceCaptureHandle /
// VoiceCaptureFactory seams. Keeps the call orchestrator unit-testable
// with no native mic backend; the real `record`-backed factory lands in
// a later slice.
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/voice_capture.dart';

void main() {
  group('voice_capture', () {
    test('NoopVoiceCaptureFactory.isSupported is false', () {
      expect(NoopVoiceCaptureFactory().isSupported, isFalse);
    });

    test('start returns a handle whose stop completes', () async {
      final h = await NoopVoiceCaptureFactory().start((_) {});
      await expectLater(h.stop(), completes);
    });

    test('start never invokes onFrame', () async {
      var calls = 0;
      final h = await NoopVoiceCaptureFactory().start((_) {
        calls += 1;
      });
      await h.stop();
      expect(calls, 0);
    });

    test('VoiceCaptureFactory subtypes can be polymorphically assigned', () {
      VoiceCaptureFactory f = NoopVoiceCaptureFactory();
      expect(f.isSupported, isFalse);
    });

    test('stop is idempotent', () async {
      final h = await NoopVoiceCaptureFactory().start((_) {});
      await h.stop();
      await h.stop();
    });
  });
}
