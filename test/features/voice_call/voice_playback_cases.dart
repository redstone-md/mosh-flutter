// The no-op playback fallback accepts frames and supports repeated stop.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';

void main() {
  group('voice_playback', () {
    test('start returns a handle whose stop completes', () async {
      final h = await NoopVoicePlaybackFactory().start();
      await expectLater(h.stop(), completes);
    });

    test('pushFrame is inert (no throw)', () async {
      final h = await NoopVoicePlaybackFactory().start();
      h.pushFrame(BigInt.one, Uint8List.fromList([1, 2, 3]));
      await h.stop();
    });

    test('stop is idempotent', () async {
      final h = await NoopVoicePlaybackFactory().start();
      await h.stop();
      await h.stop();
    });
  });
}
