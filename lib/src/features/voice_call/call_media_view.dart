import 'dart:convert';
import 'package:mosh/src/rust/native_call/types.dart' as native;

/// Bounded, public presentation metadata. Contains no engine or key handles.
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

  factory CallMediaView.fromSnapshot(native.Snapshot s) => CallMediaView(
      camera: s.camera,
      cameraRequested: s.cameraRequested,
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

  static List<CallDeviceView> _devices(List<native.Device> devices) {
    final result = <CallDeviceView>[];
    var remaining = 8000;
    for (final device in devices.take(64)) {
      final view = CallDeviceView(device.id, device.name);
      final bytes = utf8.encode(jsonEncode(view.toMap())).length;
      if (bytes > remaining) continue;
      result.add(view);
      remaining -= bytes + 1;
      if (result.length == 16) break;
    }
    return result;
  }

  Map<String, Object?> toMap() => {
        'camera': camera,
        'cameraRequested': cameraRequested,
        'cameraStarting': cameraStarting,
        'cameraFailed': cameraFailed,
        'remoteCamera': remoteCamera,
        'microphoneAvailable': microphoneAvailable,
        'reconnecting': reconnecting,
        'inputs': inputs.map((d) => d.toMap()).toList(),
        'outputs': outputs.map((d) => d.toMap()).toList(),
        'cameras': cameras.map((d) => d.toMap()).toList(),
        'input': input,
        'output': output,
        'cameraId': cameraId,
        'diagnostics': diagnostics
      };

  factory CallMediaView.fromMap(Map<Object?, Object?> m) => CallMediaView(
      camera: m['camera'] as bool,
      cameraRequested: m['cameraRequested'] as bool,
      cameraStarting: m['cameraStarting'] as bool,
      cameraFailed: m['cameraFailed'] as bool,
      remoteCamera: m['remoteCamera'] as bool,
      microphoneAvailable: m['microphoneAvailable'] as bool,
      reconnecting: m['reconnecting'] as bool,
      inputs: _read(m['inputs']),
      outputs: _read(m['outputs']),
      cameras: _read(m['cameras']),
      input: m['input'] as String?,
      output: m['output'] as String?,
      cameraId: m['cameraId'] as String?,
      diagnostics: m['diagnostics'] as String?);

  static List<CallDeviceView> _read(Object? value) => (value as List)
      .take(16)
      .map((d) => CallDeviceView.fromMap(d as Map<Object?, Object?>))
      .toList();
}

class CallDeviceView {
  const CallDeviceView(this.id, this.name);
  final String id, name;
  Map<String, String> toMap() => {'id': id, 'name': name};
  factory CallDeviceView.fromMap(Map<Object?, Object?> m) =>
      CallDeviceView(m['id'] as String, m['name'] as String);
}
