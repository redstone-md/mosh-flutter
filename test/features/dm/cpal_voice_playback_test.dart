// Unit tests for the seam-conformance of `CpalVoicePlaybackFactory`. The real
// Opus decode + cpal output + ring buffer lives in Rust (mosh-core's
// `voice_call_playback`) and the frb cdylib is not loaded under `flutter
// test`, so the decode/playback path is device-integration-validated
// separately. These tests only assert the Dart wrapper's *type* conformance
// -- that the factory is a `VoicePlaybackFactory` and that its `start`
// tear-off has the seam's `Future<VoicePlaybackHandle> Function()` shape --
// without invoking `start()` (which would hit the native lib and throw in a
// headless run).

import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/dm/cpal_voice_playback.dart';
import 'package:mosh/src/features/dm/voice_playback.dart';

void main() {
  group('CpalVoicePlaybackFactory', () {
    test('is a VoicePlaybackFactory (polymorphic assignment compiles)', () {
      // The whole point of the seam: a real factory must be assignable where
      // the seam interface is expected, so the orchestrator can swap
      // `NoopVoicePlaybackFactory` for this one without a cast.
      const VoicePlaybackFactory factory = CpalVoicePlaybackFactory();
      expect(factory, isA<VoicePlaybackFactory>());
    });

    test('start tear-off has the seam Future<VoicePlaybackHandle> shape', () {
      // Verify the *static type* of the `start` method tear-off -- not the
      // result of calling it -- so the test never touches the frb native lib
      // (absent under `flutter test`). If the return type drifts away from
      // `Future<VoicePlaybackHandle>`, the orchestrator's `await
      // factory.start()` would break at the seam.
      const factory = CpalVoicePlaybackFactory();
      expect(factory.start, isA<Future<VoicePlaybackHandle> Function()>());
    });
  });
}
