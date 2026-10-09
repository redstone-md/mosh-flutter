part of 'scriptable_bridge.dart';

mixin _BridgeNativeCalls on _ScriptableBridgeState {
  @override
  Future<void> nativeCallPrepare(
          {required String sessionId,
          required String callId,
          required bool microphone,
          required bool camera}) =>
      runScripted(
          BridgeMethod.nativeCallPrepare,
          {
            'sessionId': sessionId,
            'callId': callId,
            'microphone': microphone,
            'camera': camera
          },
          () {});
  @override
  Future<void> nativeCallChoices(
          {required String sessionId,
          required String callId,
          required bool microphone,
          required bool microphoneAllowed,
          required bool camera,
          String? input,
          String? output,
          String? cameraId}) =>
      runScripted(
          BridgeMethod.nativeCallChoices,
          {
            'sessionId': sessionId,
            'callId': callId,
            'microphone': microphone,
            'microphoneAllowed': microphoneAllowed,
            'camera': camera,
            'input': input,
            'output': output,
            'cameraId': cameraId
          },
          () {});
  @override
  Future<native_media.Snapshot?> nativeCallSnapshot(
          {required String sessionId, required String callId}) =>
      runScripted(BridgeMethod.nativeCallSnapshot,
          {'sessionId': sessionId, 'callId': callId}, () => null);
  @override
  Future<native_media.Frame?> nativeCallFrame(
          {required String sessionId,
          required String callId,
          required bool local,
          required BigInt after}) =>
      runScripted(
          BridgeMethod.nativeCallFrame,
          {
            'sessionId': sessionId,
            'callId': callId,
            'local': local,
            'after': after
          },
          () => null);
}
