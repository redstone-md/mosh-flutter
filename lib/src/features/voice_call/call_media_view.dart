import 'package:mosh/src/rust/native_call/types.dart' as native;

/// What a call view shows of the native media. Contains no engine or key
/// handles.
class CallMediaView {
  const CallMediaView(
      {required this.camera,
      required this.cameraRequested,
      required this.cameraStarting,
      required this.cameraFailed,
      required this.remoteCamera,
      required this.microphoneAvailable,
      required this.reconnecting,
      required this.inputs,
      required this.outputs,
      required this.cameras,
      this.input,
      this.output,
      this.cameraId,
      this.diagnostics});

  final bool camera, cameraRequested, cameraStarting, cameraFailed;
  final bool remoteCamera, microphoneAvailable, reconnecting;
  final List<CallDeviceView> inputs, outputs, cameras;
  final String? input, output, cameraId, diagnostics;

  /// `cameraRequested` is the session's switch, which a press changes before
  /// native media reports it.
  factory CallMediaView.fromSnapshot(native.Snapshot s,
          {bool? cameraRequested}) =>
      CallMediaView(
          camera: s.camera,
          cameraRequested: cameraRequested ?? s.cameraRequested,
          cameraStarting: s.cameraStarting,
          cameraFailed: s.cameraFailed,
          remoteCamera: s.remoteCamera,
          microphoneAvailable: s.microphoneAvailable,
          reconnecting: s.reconnecting,
          inputs: _devices(s.inputs),
          outputs: _devices(s.outputs),
          cameras: _devices(s.cameras),
          input: s.input,
          output: s.output,
          cameraId: s.cameraId,
          diagnostics: s.encoder == null || s.videoWidth == 0 || !s.camera
              ? null
              : '${s.codec ?? ""} · ${s.encoder} · ${s.videoWidth}×${s.videoHeight} · ${s.videoFps.toStringAsFixed(0)} fps');

  /// A device menu lists at most sixteen entries.
  static List<CallDeviceView> _devices(List<native.Device> devices) => [
        for (final device in devices.take(16))
          CallDeviceView(device.id, device.name)
      ];
}

class CallDeviceView {
  const CallDeviceView(this.id, this.name);
  final String id, name;
}
