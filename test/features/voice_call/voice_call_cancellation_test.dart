import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/frame_crypto.dart';
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';

import '../../support/scriptable_bridge.dart';

const _key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _prefix = 'AAAAAA==';

class _ManualCaptureFactory extends NoopVoiceCaptureFactory {
  late void Function(Uint8List) emit;

  @override
  bool get isSupported => true;

  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    emit = onFrame;
    return super.start(onFrame);
  }
}

Future<void> _attach(VoiceCallOrchestrator orchestrator,
        ScriptableBridge bridge, _ManualCaptureFactory capture, String call) =>
    orchestrator.attach(
      sessionId: 'session',
      callId: call,
      keyB64: _key,
      noncePrefixB64: _prefix,
      direction: 'caller',
      bridge: bridge,
      captureFactory: capture,
      playbackFactory: const NoopVoicePlaybackFactory(),
      onError: (error) => fail('Unexpected setup failure: $error'),
      endCall: (_, __, ___) async => fail('Unexpected call end'),
    );

void main() {
  test('a frame being sealed when detached never reaches the bridge', () async {
    final bridge = ScriptableBridge();
    final capture = _ManualCaptureFactory();
    final orchestrator = VoiceCallOrchestrator();
    addTearDown(orchestrator.detach);
    await _attach(orchestrator, bridge, capture, 'ended');

    // Real AES-GCM sealing yields; detach invalidates the captured key first.
    capture.emit(Uint8List.fromList([1, 2, 3]));
    expect(bridge.countOf(BridgeMethod.callSendFrame), 0);
    await orchestrator.detach();
    await Future<void>.delayed(Duration.zero);

    expect(bridge.countOf(BridgeMethod.callSendFrame), 0);
  });

  test('reattaching sends new audio without reviving a pending old frame',
      () async {
    final bridge = ScriptableBridge();
    final oldCapture = _ManualCaptureFactory();
    final newCapture = _ManualCaptureFactory();
    final orchestrator = VoiceCallOrchestrator();
    addTearDown(orchestrator.detach);
    await _attach(orchestrator, bridge, oldCapture, 'old');

    oldCapture.emit(Uint8List.fromList([1, 2, 3]));
    final detached = orchestrator.detach();
    final attached = _attach(orchestrator, bridge, newCapture, 'replacement');
    await Future.wait([detached, attached]);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.countOf(BridgeMethod.callSendFrame), 0);

    final newAudio = Uint8List.fromList([4, 5, 6]);
    newCapture.emit(newAudio);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.argValues<String>(BridgeMethod.callSendFrame, 'callId'),
        ['replacement']);
    final frame =
        bridge.argValues<Uint8List>(BridgeMethod.callSendFrame, 'frame').single;
    final opened = await openFrame(await importCallKey(_key), _prefix, frame);
    expect(opened?.payload, newAudio);
  });
}
