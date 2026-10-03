import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/rust/device_link/types.dart';

DeviceLinkSnapshot setupDeviceSnapshot({
  DeviceLinkPhase phase = DeviceLinkPhase.idle,
  DeviceLinkRole? role,
  bool canJoin = true,
  bool revoked = false,
  int devices = 1,
}) =>
    DeviceLinkSnapshot(
      role: role,
      revoked: revoked,
      revocations: const [],
      userId: 'user',
      ownDeviceId: 'device-0',
      canJoin: canJoin,
      phase: phase,
      confirmationCode:
          phase == DeviceLinkPhase.awaitingConfirmation ? 'ABCDEF123456' : null,
      devices: List.generate(
          devices,
          (index) => DeviceDescriptor(
              deviceId: 'device-$index',
              signingPublicKey: 'key-$index',
              mossPeerId: 'peer-$index',
              name: 'Desktop $index')),
    );

/// Drives the existing device-link controller seam without native handles.
class ScriptableDeviceLink extends DeviceLinkController {
  ScriptableDeviceLink({DeviceLinkSnapshot? snapshot})
      : current = snapshot ?? setupDeviceSnapshot();

  DeviceLinkSnapshot current;
  Object? buildError;
  Object? actionError;
  DeviceLinkSnapshot? snapshotAfterCancel;
  final List<String> imported = [];
  int cancellations = 0;

  @override
  Future<DeviceLinkSnapshot> build() async {
    if (buildError != null) throw buildError!;
    return current;
  }

  void publish(DeviceLinkSnapshot snapshot) {
    current = snapshot;
    state = AsyncData(snapshot);
  }

  @override
  Future<void> joinLink(String uri, String name) async {
    if (actionError != null) throw actionError!;
    imported.add(uri);
    publish(setupDeviceSnapshot(
        phase: DeviceLinkPhase.awaitingConfirmation,
        role: DeviceLinkRole.joining));
  }

  @override
  Future<void> cancel() async {
    if (actionError != null) throw actionError!;
    cancellations++;
    publish(snapshotAfterCancel ?? setupDeviceSnapshot());
  }
}
