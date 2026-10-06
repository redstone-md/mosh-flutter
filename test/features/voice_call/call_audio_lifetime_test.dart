import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/frame_codec.dart';
import 'package:mosh/src/features/voice_call/frame_crypto.dart';
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';

import '../../support/scriptable_bridge.dart';
import '../../support/voice_call_fakes.dart';

const _key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _nonce = 'AAAAAA==';

class _DelayedCapture implements VoiceCaptureFactory {
  final started = Completer<void>();
  final handle = Completer<VoiceCaptureHandle>();
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List) onFrame) {
    started.complete();
    return handle.future;
  }
}

Future<void> _attach(VoiceCallOrchestrator audio, String id,
        VoiceCaptureFactory capture, RecordingPlayback playback,
        {String sessionId = 'session',
        ScriptableBridge? bridge,
        void Function(String?)? onError}) =>
    audio.attach(
      sessionId: sessionId,
      callId: id,
      keyB64: _key,
      noncePrefixB64: _nonce,
      direction: 'caller',
      bridge: bridge ?? ScriptableBridge(),
      captureFactory: capture,
      playbackFactory: playback,
      onError: onError ?? (error) => fail('$error'),
      endCall: (_, __, ___) async {},
    );

void main() {
  test('replacement waits for teardown and old-owner disposal cannot stop it',
      () async {
    final audio = VoiceCallOrchestrator();
    final capture = RecordingCapture();
    final playback = RecordingPlayback();
    await _attach(audio, 'first', capture, playback);
    capture.stopping = Completer<void>();
    final second = _attach(audio, 'second', capture, playback);
    await Future<void>.delayed(Duration.zero);
    expect(capture.starts, 1);
    expect(playback.starts, 1);
    expect(playback.stops, 1,
        reason: 'A stalled microphone stop cannot retain the output');
    expect(audio.isAttached, isFalse);
    capture.stopping!.complete();
    await second;
    expect(capture.starts, 2);
    expect(playback.starts, 2);
    expect(capture.stops, 1);
    expect(playback.stops, 1);
    await audio.detach(call: ('session', 'first'));
    expect(audio.isAttached, isTrue);
    await audio.detach(call: ('session', 'second'));
    expect(capture.stops, 2);
    expect(playback.stops, 2);
  });

  for (final pending in [false, true]) {
    test('old DM cleanup cannot stop a reused call ID; pending: $pending',
        () async {
      final audio = VoiceCallOrchestrator();
      addTearDown(audio.detach);
      final playback = RecordingPlayback();
      await _attach(audio, 'shared', RecordingCapture(), playback,
          sessionId: 'old');
      final delayed = _DelayedCapture();
      final capture = RecordingCapture();
      final replacement = _attach(
          audio, 'shared', pending ? delayed : capture, playback,
          sessionId: 'new');
      if (pending) {
        await delayed.started.future;
      } else {
        await replacement;
      }
      final obsolete = audio.detach(call: ('old', 'shared'));
      if (pending) delayed.handle.complete(await capture.start((_) {}));
      await Future.wait([replacement, obsolete]);
      expect(audio.isAttached, isTrue);
      expect(playback.stops, 1);
      expect(capture.stops, 0);
      await audio.detach(call: ('new', 'shared'));
      expect(capture.stops, 1);
      expect(playback.stops, 2);
    });
  }

  test('capture returned after cancellation is stopped before replacement',
      () async {
    final audio = VoiceCallOrchestrator();
    final delayed = _DelayedCapture();
    final playback = RecordingPlayback();
    final first = _attach(audio, 'first', delayed, playback);
    await delayed.started.future;
    final nextCapture = RecordingCapture();
    final second = _attach(audio, 'second', nextCapture, playback);
    final lateCapture = RecordingCapture()..stopping = Completer<void>();
    delayed.handle.complete(await lateCapture.start((_) {}));
    await Future<void>.delayed(Duration.zero);
    expect(playback.stops, 1,
        reason: 'Cancellation releases output while late capture stops');
    expect(nextCapture.starts, 0);
    lateCapture.stopping!.complete();
    await first;
    await second;
    expect(lateCapture.stops, 1);
    expect(playback.stops, 1);
    expect(nextCapture.starts, 1);
    expect(audio.isAttached, isTrue);
    await audio.detach();
  });

  test('failure from an obsolete startup cannot end the replacement', () async {
    final audio = VoiceCallOrchestrator();
    final delayed = _DelayedCapture();
    final playback = RecordingPlayback();
    final errors = <String?>[];
    final first =
        _attach(audio, 'first', delayed, playback, onError: errors.add);
    await delayed.started.future;
    final second = _attach(audio, 'second', RecordingCapture(), playback);
    delayed.handle.completeError(StateError('old setup failure'));
    await first;
    await second;
    expect(errors, isEmpty);
    expect(playback.stops, 1);
    expect(audio.isAttached, isTrue);
    await audio.detach();
  });

  test('a drain completing after detach cannot feed the stopped player',
      () async {
    final bridge = ScriptableBridge()..hold(BridgeMethod.callDrainFrames);
    final key = await importCallKey(_key);
    bridge.seedCallFrames([
      await sealFrame(key, _nonce, BigInt.zero, CALLEE_DIRECTION_BIT,
          Uint8List.fromList([1, 2, 3]))
    ]);
    final playback = RecordingPlayback();
    final audio = VoiceCallOrchestrator();
    await _attach(audio, 'first', RecordingCapture(), playback, bridge: bridge);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(bridge.countOf(BridgeMethod.callDrainFrames), 1);
    await audio.detach();
    bridge.release(BridgeMethod.callDrainFrames);
    await Future<void>.delayed(Duration.zero);
    expect(playback.frames, 0);
    expect(playback.stops, 1);
  });
}
