import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_list.dart';
import 'package:mosh/src/features/device_link/device_revocation_dialog.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/pump.dart';

const own = DeviceDescriptor(
    deviceId: 'own',
    signingPublicKey: 'own-key',
    mossPeerId: 'own-peer',
    name: 'Main desktop');
const other = DeviceDescriptor(
    deviceId: 'other',
    signingPublicKey: 'other-key',
    mossPeerId: 'other-peer',
    name: 'Office desktop');

void main() {
  testWidgets(
      'only another device offers removal and requires a named confirmation',
      (tester) async {
    String? removed;
    await pumpScreen(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => LinkedDeviceList(
                      snapshot: const DeviceLinkSnapshot(
                          userId: 'user',
                          ownDeviceId: 'own',
                          devices: [own, other],
                          phase: DeviceLinkPhase.idle,
                          canJoin: false,
                          revoked: false,
                          revocations: []),
                      onRemove: (device) async {
                        if (await confirmDeviceRemoval(context, device.name)) {
                          removed = device.deviceId;
                        }
                      },
                    ))));
    expect(find.byTooltip('Remove device'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove device'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Office desktop?'), findsOneWidget);
    expect(find.textContaining('Already received messages stay on that device'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, isNull);
    await tester.tap(find.byTooltip('Remove device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove device'));
    await tester.pumpAndSettle();
    expect(removed, 'other');
  });

  for (final state in DeviceRevocationState.values) {
    testWidgets('shows persisted $state removal status', (tester) async {
      await pumpScreen(
          tester,
          Scaffold(
              body: LinkedDeviceList(
                  snapshot: DeviceLinkSnapshot(
            userId: 'user',
            ownDeviceId: 'own',
            devices: const [own],
            phase: DeviceLinkPhase.idle,
            canJoin: false,
            revoked: false,
            revocations: [DeviceRevocationStatus(device: other, state: state)],
          ))));
      expect(find.text('Office desktop'), findsOneWidget);
      expect(
          find.text(state == DeviceRevocationState.pending
              ? 'Removal pending'
              : 'Removal applied'),
          findsOneWidget);
      expect(find.byTooltip('Remove device'), findsNothing);
    });
  }
}
