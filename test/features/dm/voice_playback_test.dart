// Parity tests for `voice_playback` (lib/src/features/dm/voice_playback.dart)
// -- the seam between the call orchestrator and an actual audio playback
// pipeline, mirroring React's `audio-playback.ts` `VoicePlaybackHandle`
// (`{ pushFrame(seq, payload); stop(): void }`) + `startVoicePlayback()`
// factory. The real `media_kit`-backed playback lands in a later slice; these
// tests pin the [NoopVoicePlaybackFactory] contract (inert feed, idempotent
// `stop`, polymorphic factory) and -- critically -- prove a started handle
// is usable as a [CallFrameSink] for [drainCallFrames] with no adapter (Dart
// interfaces are nominal, so [_NoopHandle] declares `implements CallFrameSink`).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/dm/call_drain.dart';
import 'package:mosh/src/features/dm/voice_playback.dart';

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

    test('VoicePlaybackHandle satisfies CallFrameSink structurally', () async {
      // A consumer that takes a [CallFrameSink] -- the exact shape
      // [drainCallFrames] expects for its `playback` param. Passing a
      // started [VoicePlaybackHandle] here proves the orchestrator can feed
      // the handle straight into [drainCallFrames] with no adapter.
      Future<int> feedAndCount(CallFrameSink sink) async {
        sink.pushFrame(BigInt.one, Uint8List.fromList([1]));
        sink.pushFrame(BigInt.from(2), Uint8List.fromList([2]));
        return 2;
      }

      final h = await NoopVoicePlaybackFactory().start();
      expect(await feedAndCount(h), 2);
      await h.stop();
    });

    test('VoicePlaybackFactory subtypes can be polymorphically assigned', () async {
      VoicePlaybackFactory f = NoopVoicePlaybackFactory();
      final h = await f.start();
      await h.stop();
    });
  });
}
