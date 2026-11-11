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
          String? cameraId,
          bool cameraSelection = false}) =>
      native_call_api.setChoices(
          sessionId: sessionId,
          callId: callId,
          microphone: microphone,
          microphoneAllowed: microphoneAllowed,
          camera: camera,
          input: input,
          output: output,
          cameraId: cameraId,
          cameraSelection: cameraSelection);

  Future<native_media.Snapshot?> nativeCallSnapshot(
          {required String sessionId, required String callId}) =>
      native_call_api.snapshot(sessionId: sessionId, callId: callId);

  Future<void> nativeCallShowVideoAt(
          {required native_media.Surface local,
          required native_media.Surface remote}) =>
      native_call_api.showVideoAt(local: local, remote: remote);

  /// The main window's video textures by export address; zero for none.
  Future<void> nativeCallShowVideoIn(
          {required int local, required int remote}) =>
      native_call_api.showVideoIn(local: local, remote: remote);
}
