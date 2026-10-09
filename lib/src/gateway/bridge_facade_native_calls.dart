part of 'bridge_facade.dart';

mixin NativeCallBridge {
  Future<void> nativeCallPrepare(
          {required String sessionId,
          required String callId,
          required bool microphone,
          required bool camera}) =>
      native_call_api.prepare(
          sessionId: sessionId,
          callId: callId,
          microphone: microphone,
          camera: camera);

  Future<void> nativeCallChoices(
          {required String sessionId,
          required String callId,
          required bool microphone,
          required bool microphoneAllowed,
          required bool camera,
          String? input,
          String? output,
          String? cameraId}) =>
      native_call_api.setChoices(
          sessionId: sessionId,
          callId: callId,
          microphone: microphone,
          microphoneAllowed: microphoneAllowed,
          camera: camera,
          input: input,
          output: output,
          cameraId: cameraId);

  Future<native_media.Snapshot?> nativeCallSnapshot(
          {required String sessionId, required String callId}) =>
      native_call_api.snapshot(sessionId: sessionId, callId: callId);

  Future<native_media.Frame?> nativeCallFrame(
          {required String sessionId,
          required String callId,
          required bool local,
          required BigInt after}) =>
      native_call_api.frame(
          sessionId: sessionId, callId: callId, local: local, after: after);
}
