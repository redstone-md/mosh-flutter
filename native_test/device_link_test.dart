import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';
import 'package:mosh/src/rust/frb_generated.dart';
import 'package:mosh/src/rust/api/private_dm.dart' as setup;
import 'package:mosh/src/rust/api/device_link.dart' as link;
import 'package:mosh/src/rust/device_link/types.dart';

import '../test/support/pump.dart';
import 'support/native_peer.dart';

void main() {
  late Directory appDir;

  setUpAll(() async {
    appDir = await Directory.systemTemp.createTemp('mosh-native-link-');
    const overrideLibrary = String.fromEnvironment('MOSH_CORE_TEST_LIBRARY');
    final platformLibrary = Platform.isWindows
        ? 'mosh-core/target/debug/mosh_core.dll'
        : Platform.isMacOS
            ? 'mosh-core/target/debug/libmosh_core.dylib'
            : 'mosh-core/target/debug/libmosh_core.so';
    final library = overrideLibrary.isEmpty ? platformLibrary : overrideLibrary;
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    await setup.setAppDataDir(path: appDir.path);
    await setup.setHistoryDek(dek: List.filled(32, 77));
  });

  tearDownAll(() async {
    RustLib.dispose();
    // The native singleton retains the DB until this test process exits.
    // Unix permits removing open files; Windows cleanup runs after the process.
    if (!Platform.isWindows) await appDir.delete(recursive: true);
  });

  testWidgets(
      'real bridge creates a QR, rejects bad input and approves an independent desktop',
      (tester) async {
    await pumpScreen(
        tester,
        const Scaffold(
            body: SingleChildScrollView(
          child: Padding(
              padding: EdgeInsets.all(16), child: DevicesSettingsSection()),
        )),
        settle: false);
    await pumpUntil(tester, find.text('Name of this desktop'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Name of this desktop'), 'Main desktop');
    await tapVisible(
        tester, find.text('Link this desktop to an existing user'));
    await pumpUntil(tester, find.text('Copy link'));
    final qr = await tester.runAsync(link.snapshot);
    expect(qr!.qrUri, startsWith('mosh://device-link/'));
    await tapVisible(tester, find.text('Cancel link'));
    await pumpUntil(tester, find.text('Connect to new desktop'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Or paste the new desktop link'),
        'broken');
    await tapVisible(tester, find.text('Connect to new desktop'));
    await pumpUntil(
        tester, find.textContaining('This is not a valid device QR'));

    final peer = await tester.runAsync(NativePeer.start);
    addTearDown(peer!.close);
    final request = await tester.runAsync(
        () => peer.ask({'action': 'qr', 'argument': 'Second desktop'}));
    await tester.enterText(
        find.widgetWithText(TextField, 'Or paste the new desktop link'),
        request!['qr_uri'] as String);
    await tapVisible(tester, find.text('Connect to new desktop'));
    await pumpUntil(tester, find.text('Code from the new desktop'));
    final confirmation =
        await tester.runAsync(() => peer.waitPhase('AwaitingConfirmation'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Code from the new desktop'),
        '000000000000');
    await tapVisible(tester, find.text('Approve device'));
    await pumpUntil(tester, find.textContaining('The code does not match'));
    expect((await tester.runAsync(link.snapshot))!.devices.length, 1);
    await tester.enterText(
        find.widgetWithText(TextField, 'Code from the new desktop'),
        confirmation!['confirmation_code'] as String);
    await tapVisible(tester, find.text('Approve device'));
    await pumpUntil(tester, find.textContaining('Device linked.'));
    final linked = await tester.runAsync(link.snapshot);
    final other = await tester.runAsync(() => peer.waitPhase('Linked'));
    expect(linked!.userId, other!['user_id']);
    expect(linked.devices.length, 2);
    expect(find.text('Second desktop'), findsOneWidget);
    expect(linked.devices.map((d) => d.mossPeerId).toSet().length, 2);
    await tapVisible(tester, find.byTooltip('Remove device'));
    await pumpUntil(tester, find.text('Remove Second desktop?'));
    await tapVisible(tester, find.text('Cancel'));
    expect((await tester.runAsync(link.snapshot))!.devices.length, 2);
    await tapVisible(tester, find.byTooltip('Remove device'));
    await pumpUntil(tester, find.text('Remove Second desktop?'));
    await tapVisible(tester, find.text('Remove device'));
    await pumpUntil(tester, find.text('Removal applied'));
    final removed = await tester.runAsync(link.snapshot);
    expect(removed!.devices.length, 1);
    expect(removed.revocations.single.state, DeviceRevocationState.applied);
    expect(removed.revocations.single.device.deviceId, other['own_device_id']);
    final revoked = await tester.runAsync(() async {
      final until = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(until)) {
        final snapshot = await peer.ask({'action': 'snapshot'});
        if (snapshot['revoked'] == true) return snapshot;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('Independent desktop must receive the signed removal');
    });
    expect(revoked!['user_id'], linked.userId);
    await approveFreshPeer(tester, peer);
    await tester.runAsync(() => peer.ask({
          'action': 'revoke',
          'argument': linked.ownDeviceId,
        }));
    await requestFreshAccess(tester, peer, linked.userId);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> approveFreshPeer(WidgetTester tester, NativePeer peer) async {
  final request = await tester
      .runAsync(() => peer.ask({'action': 'qr', 'argument': 'Second desktop'}));
  await tester.enterText(
      find.widgetWithText(TextField, 'Or paste the new desktop link'),
      request!['qr_uri'] as String);
  await tapVisible(tester, find.text('Connect to new desktop'));
  await pumpUntil(tester, find.text('Code from the new desktop'));
  final ready =
      await tester.runAsync(() => peer.waitPhase('AwaitingConfirmation'));
  await tester.enterText(
      find.widgetWithText(TextField, 'Code from the new desktop'),
      ready!['confirmation_code'] as String);
  await tapVisible(tester, find.text('Approve device'));
  await pumpUntil(tester, find.textContaining('Device linked.'));
  await tester.runAsync(() => peer.waitPhase('Linked'));
}

Future<void> requestFreshAccess(
    WidgetTester tester, NativePeer peer, String userId) async {
  await pumpUntil(tester, find.text('Request access again'));
  expect(find.textContaining('This desktop was removed.'), findsOneWidget);
  expect(find.byTooltip('Remove device'), findsNothing);
  expect(find.text('Name of this desktop'), findsNothing);
  expect(find.text('Connect to new desktop'), findsNothing);
  await tapVisible(tester, find.text('Request access again'));
  await pumpUntil(tester, find.text('Copy link'));
  final request = await tester.runAsync(link.snapshot);
  await tester.runAsync(
      () => peer.ask({'action': 'import', 'argument': request!.qrUri}));
  await pumpUntil(
      tester,
      find.text(
          'Enter this code on your trusted desktop to approve this device.'));
  final ready = await tester.runAsync(link.snapshot);
  await tester.runAsync(() =>
      peer.ask({'action': 'approve', 'argument': ready!.confirmationCode}));
  await pumpUntil(tester, find.textContaining('Device linked.'));
  final joined = await tester.runAsync(link.snapshot);
  expect(joined!.revoked, isFalse);
  expect(joined.userId, userId);
  expect(joined.devices.length, 2);
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> pumpUntil(WidgetTester tester, Finder target) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (target.evaluate().isEmpty) {
    expect(DateTime.now().isBefore(deadline), isTrue,
        reason: 'Native UI must reach $target');
    await tester.pump(const Duration(seconds: 1));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}
