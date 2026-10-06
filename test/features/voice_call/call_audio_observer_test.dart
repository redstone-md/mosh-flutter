import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';
import '../../../integration_test/support/call_audio_observer.dart';

class _Handle implements VoiceCaptureHandle, VoicePlaybackHandle {
  final stopped = Completer<void>();
  @override
  Future<void> stop() => stopped.future;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {}
}

class _Capture extends NoopVoiceCaptureFactory {
  _Capture(this.handle);
  final _Handle handle;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) async =>
      handle;
}

class _Playback extends NoopVoicePlaybackFactory {
  _Playback(this.handle);
  final _Handle handle;
  @override
  Future<VoicePlaybackHandle> start() async => handle;
}

void main() {
  for (final capture in [true, false]) {
    for (final success in [true, false]) {
      test('observer counts completed stop: capture=$capture success=$success',
          () async {
        final handle = _Handle();
        final observer = CallAudioObserver(
            captureSource: _Capture(handle), playbackSource: _Playback(handle));
        final stop = capture
            ? (await observer.capture.start((_) {})).stop
            : (await observer.playback.start()).stop;
        int stops() => capture ? observer.captureStops : observer.playerStops;
        final ending = stop();
        expect(stops(), 0, reason: 'A pending stop is not completed cleanup');
        if (success) {
          handle.stopped.complete();
          await ending;
          expect(stops(), 1);
        } else {
          final failure = expectLater(ending, throwsStateError);
          handle.stopped.completeError(StateError('stop failed'));
          await failure;
          expect(stops(), 0, reason: 'A failed stop cannot prove cleanup');
        }
      });
    }
  }
}
