import 'package:mosh/src/features/device_link/device_link_commands.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import 'scripted_calls.dart';

enum DeviceLinkMethod { snapshot, beginLink, joinLink, approve, cancel, revoke }

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

/// Script commands below the real Flutter workflow. Native proofs use real Rust.
class ScriptableDeviceLink extends DeviceLinkCommands
    with ScriptedEngine<DeviceLinkMethod> {
  ScriptableDeviceLink({DeviceLinkSnapshot? snapshot})
      : current = snapshot ?? setupDeviceSnapshot();

  DeviceLinkSnapshot current;
  Object? buildError;
  Object? actionError;
  DeviceLinkSnapshot? snapshotAfterCancel;
  final List<String> imported = [];
  int cancellations = 0;

  @override
  Future<DeviceLinkSnapshot> snapshot() =>
      runScripted(DeviceLinkMethod.snapshot, {}, () {
        if (buildError != null) throw buildError!;
        return current;
      });

  void publish(DeviceLinkSnapshot snapshot) {
    current = snapshot;
  }

  @override
  Future<DeviceLinkSnapshot> joinLink(String uri, String name) =>
      _command(DeviceLinkMethod.joinLink, {'uri': uri, 'name': name}, () {
        imported.add(uri);
        return setupDeviceSnapshot(
            phase: DeviceLinkPhase.awaitingConfirmation,
            role: DeviceLinkRole.joining);
      });

  @override
  Future<DeviceLinkSnapshot> cancel() =>
      _command(DeviceLinkMethod.cancel, {}, () {
        cancellations++;
        return snapshotAfterCancel ?? setupDeviceSnapshot();
      });

  @override
  Future<DeviceLinkSnapshot> beginLink() => _command(
      DeviceLinkMethod.beginLink,
      {},
      () => setupDeviceSnapshot(
          phase: DeviceLinkPhase.showingQr, role: DeviceLinkRole.authorizing));

  @override
  Future<DeviceLinkSnapshot> approve(String code) => _command(
      DeviceLinkMethod.approve,
      {'code': code},
      () => setupDeviceSnapshot(
          phase: DeviceLinkPhase.linked, canJoin: false, devices: 2));

  @override
  Future<DeviceLinkSnapshot> revoke(String deviceId) => _command(
      DeviceLinkMethod.revoke,
      {'deviceId': deviceId},
      () => setupDeviceSnapshot(
          canJoin: false, devices: current.devices.length - 1));

  Future<DeviceLinkSnapshot> _command(DeviceLinkMethod method,
          Map<String, Object?> args, DeviceLinkSnapshot Function() result) =>
      runScripted(method, args, () {
        if (actionError != null) throw actionError!;
        return current = result();
      });
}
