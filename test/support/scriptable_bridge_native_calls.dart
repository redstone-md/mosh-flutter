part of 'scriptable_bridge.dart';

mixin _BridgeNativeCalls on _ScriptableBridgeState {
  @override
  Future<void> nativeCallPrepare({
    required String sessionId,
    required String callId,
    required bool microphone,
    required bool camera,
  }) =>
      runScripted(
          BridgeMethod.nativeCallPrepare,
          {
            'sessionId': sessionId,
            'callId': callId,
            'microphone': microphone,
            'camera': camera,
          },
          () {});
  @override
  Future<void> nativeCallChoices({
    required String sessionId,
    required String callId,
    required bool microphone,
    required bool microphoneAllowed,
    required bool camera,
    String? input,
    String? output,
    String? cameraId,
    bool cameraSelection = false,
  }) =>
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
          'cameraId': cameraId,
          'cameraSelection': cameraSelection,
        },
        () => _applyChoices(
          microphone,
          microphoneAllowed,
          camera,
          input: input,
          output: output,
          cameraId: cameraId,
        ),
      );

  /// The engine adopts the choices, so a seeded snapshot reports them back
  /// the way `native_call::State::reflect_choices` does.
  void _applyChoices(
    bool microphone,
    bool allowed,
    bool camera, {
    String? input,
    String? output,
    String? cameraId,
  }) {
    final s = _nativeCallSnapshot;
    if (s == null) return;
    _nativeCallSnapshot = native_media.Snapshot(
      sessionId: s.sessionId,
      callId: s.callId,
      ready: s.ready,
      microphone: microphone && allowed && s.inputs.isNotEmpty,
      microphoneRequested: microphone,
      microphoneAvailable: allowed &&
          s.inputs.any((device) => input == null || device.id == input),
      camera: camera,
      cameraRequested: camera,
      cameraStarting: s.cameraStarting,
      cameraFailed: s.cameraFailed,
      remoteCamera: s.remoteCamera,
      reconnecting: s.reconnecting,
      failed: s.failed,
      encoder: s.encoder,
      codec: s.codec,
      videoWidth: s.videoWidth,
      videoHeight: s.videoHeight,
      videoFps: s.videoFps,
      packetsDropped: s.packetsDropped,
      inputs: s.inputs,
      outputs: s.outputs,
      cameras: s.cameras,
      input: input,
      output: output,
      cameraId: cameraId,
    );
  }

  @override
  Future<native_media.Snapshot?> nativeCallSnapshot({
    required String sessionId,
    required String callId,
  }) =>
      runScripted(
          BridgeMethod.nativeCallSnapshot,
          {
            'sessionId': sessionId,
            'callId': callId,
          },
          () => _nativeCallSnapshot);
  @override
  Future<native_media.Frame?> nativeCallFrame({
    required String sessionId,
    required String callId,
    required bool local,
    required BigInt after,
  }) =>
      runScripted(
          BridgeMethod.nativeCallFrame,
          {
            'sessionId': sessionId,
            'callId': callId,
            'local': local,
            'after': after,
          },
          () => null);

  @override
  Future<void> nativeCallShowVideoAt({
    required native_media.Surface local,
    required native_media.Surface remote,
  }) =>
      runScripted(
          BridgeMethod.nativeCallShowVideoAt,
          {
            'local': [local.width, local.height],
            'remote': [remote.width, remote.height],
          },
          () {});
}
