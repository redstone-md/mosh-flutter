import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/device_link/device_list.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../support/pump.dart';

const userId =
    'a5bbed9b207a36ad1aa192f242f6789d858f49a0699c0ba1d488c6d70234acb4';
const deviceId =
    'd661135475c33f37c43e897ad2d1b5651114b021acec2830983708c58c1def2b';

void main() {
  testWidgets('long ids read as head…tail, never wrapped mid-id',
      (tester) async {
    await pumpScreen(
        tester,
        const Scaffold(
            body: LinkedDeviceList(
                snapshot: DeviceLinkSnapshot(
          userId: userId,
          ownDeviceId: deviceId,
          devices: [
            DeviceDescriptor(
                deviceId: deviceId,
                signingPublicKey: 'key',
                mossPeerId: 'peer',
                name: 'Desktop'),
          ],
          phase: DeviceLinkPhase.idle,
          canJoin: false,
          revoked: false,
          revocations: [],
        ))));

    expect(find.text('a5bbed9b…acb4'), findsOneWidget);
    expect(find.text('d6611354…ef2b'), findsOneWidget);
    expect(find.textContaining(userId), findsNothing);
    expect(find.textContaining(deviceId), findsNothing);
  });
}
