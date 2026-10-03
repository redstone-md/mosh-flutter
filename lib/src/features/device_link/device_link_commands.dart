import 'package:mosh/src/rust/api/device_link.dart' as api;
import 'package:mosh/src/rust/device_link/types.dart';

/// Feature-local native commands. Flutter tests replace commands, not workflow.
class DeviceLinkCommands {
  Future<DeviceLinkSnapshot> snapshot() => api.snapshot();
  Future<DeviceLinkSnapshot> beginLink() => api.beginLink();
  Future<DeviceLinkSnapshot> joinLink(String uri, String name) =>
      api.joinLink(uri: uri, deviceName: name);
  Future<DeviceLinkSnapshot> approve(String code) =>
      api.approve(confirmationCode: code);
  Future<DeviceLinkSnapshot> cancel() => api.cancel();
  Future<DeviceLinkSnapshot> revoke(String deviceId) =>
      api.revoke(deviceId: deviceId);
}
