import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/native_call_session.dart';
import '../../support/scriptable_bridge.dart';

void main() {
  NativeCallSession session(
          ScriptableBridge bridge, Future<bool> Function() permission) =>
      NativeCallSession(
          sessionId: 'dm',
          callId: 'call',
          bridge: bridge,
          requestMicrophone: () async => true,
          requestCamera: permission,
          onState: () {},
          onFrame: (_) {});

  test('video preparation waits for permission; refusal keeps audio available',
      () async {
    final bridge = ScriptableBridge();
    final permission = Completer<bool>();
    final call = session(bridge, () => permission.future);
    final start = call.start(camera: true);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 0);
    permission.complete(false);
    await start;
    expect(bridge.lastCall(BridgeMethod.nativeCallPrepare)!.arg<bool>('camera'),
        false);
    await call.confirm();
    expect(
        bridge
            .lastCall(BridgeMethod.nativeCallChoices)!
            .arg<bool>('microphoneAllowed'),
        true);
    expect(bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<bool>('camera'),
        false);
    call.stop();
  });

  test('ending while the camera prompt is open cannot start capture later',
      () async {
    final bridge = ScriptableBridge();
    final permission = Completer<bool>();
    final call = session(bridge, () => permission.future);
    final start = call.start(camera: true);
    call.stop();
    permission.complete(true);
    await start;
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 0);
  });

  test('camera toggle requests permission without interrupting microphone',
      () async {
    final bridge = ScriptableBridge();
    var prompts = 0;
    final call = session(bridge, () async {
      prompts++;
      return prompts > 1;
    });
    await call.start();
    await call.confirm();
    await call.toggleCamera();
    expect(bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<bool>('camera'),
        false);
    await call.toggleCamera();
    expect(bridge.lastCall(BridgeMethod.nativeCallChoices)!.arg<bool>('camera'),
        true);
    await call.toggleCamera();
    expect(prompts, 2);
    expect(
        bridge
            .lastCall(BridgeMethod.nativeCallChoices)!
            .arg<bool>('microphoneAllowed'),
        true);
    call.stop();
  });
}
