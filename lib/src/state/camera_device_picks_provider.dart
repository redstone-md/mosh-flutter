import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/rust/api/native_call.dart' as api;
import 'package:mosh/src/rust/native_call/types.dart' show Device;

/// Enumeration does not open the camera or create a call. Unstable device IDs
/// remain usable inside a call, but cannot identify a default across restarts.
final cameraDevicesProvider = FutureProvider.autoDispose<List<Device>>(
    (ref) async =>
        (await api.listCameras()).where((device) => device.stable).toList());

final defaultCameraProvider =
    NotifierProvider<DefaultCameraNotifier, String?>(DefaultCameraNotifier.new);

class DefaultCameraNotifier extends Notifier<String?> {
  @override
  String? build() => api.defaultCameraId();

  void set(String? id) {
    api.setDefaultCamera(cameraId: id);
    state = id;
  }
}
