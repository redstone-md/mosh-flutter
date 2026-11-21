// Device linking scenes: Settings > Devices, the link and join flows, and
// the Android camera scanner.
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/device_link/device_link_flow.dart';
import 'package:mosh/src/features/device_link/device_link_import_form.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/device_link/device_qr_scanner.dart';
import 'package:mosh/src/features/device_link/devices_settings_section.dart';
import 'package:mosh/src/rust/device_link/types.dart';

import '../../../test/support/device_link_fixture.dart';
import '../../../test/support/message_selection.dart' show captureClipboard;
import '../../../test/support/scanner_platform.dart';
import '../../../test/support/scriptable_device_link.dart';
import 'account_shell.dart';
import 'harness.dart';

DeviceDescriptor _device(String name, String hex) => DeviceDescriptor(
    deviceId: hex * 8,
    signingPublicKey: 'k$hex',
    mossPeerId: 'p$hex',
    name: name);

final _own = _device('alex-workstation', '7f3a9c1e');
final _phone = _device('Pixel 8', 'c41d07b2');
final _laptop = _device('Studio MacBook Air', '9e62a5f0');

DeviceLinkSnapshot _snapshot({
  DeviceLinkPhase phase = DeviceLinkPhase.idle,
  DeviceLinkRole? role,
  List<DeviceDescriptor>? devices,
  bool canJoin = false,
  bool revoked = false,
  List<DeviceRevocationStatus> revocations = const [],
  DeviceDescriptor? pending,
  DeviceLinkErrorKind? error,
}) =>
    DeviceLinkSnapshot(
      role: role,
      revoked: revoked,
      revocations: revocations,
      userId: '4b8e2d61' * 8,
      ownDeviceId: _own.deviceId,
      devices: devices ?? [_own],
      canJoin: canJoin,
      phase: phase,
      qrUri: phase == DeviceLinkPhase.showingQr ? deviceLinkQrFixture() : null,
      confirmationCode:
          phase == DeviceLinkPhase.awaitingConfirmation ? 'K7Q2M9XD4PLA' : null,
      pendingDevice: pending,
      error: error,
    );

/// Settings > Devices over [commands]; no polling, refresh stays explicit.
/// A running flow is scrolled to the top, as it is the part in use.
Future<void> _devices(
    WidgetTester tester, Size size, ScriptableDeviceLink commands,
    {bool settle = true}) async {
  await openSettingsSection(tester, size, 'Devices',
      settle: settle,
      overrides: [
        deviceLinkCommandsProvider.overrideWithValue(commands),
        deviceLinkPollIntervalProvider.overrideWithValue(null),
      ]);
  await _focusFlow(tester, settle: settle);
}

Future<void> _focusFlow(WidgetTester tester, {bool settle = true}) async {
  final flow = find.byType(DeviceLinkFlow);
  if (flow.evaluate().isEmpty) return;
  await tester.ensureVisible(flow);
  settle ? await tester.pumpAndSettle() : await frames(tester, 3);
}

FigmaScene _state(String id, String title, DeviceLinkSnapshot snapshot,
        {bool settle = true}) =>
    FigmaScene(
        id,
        title,
        (tester, size) => _devices(
            tester, size, ScriptableDeviceLink(snapshot: snapshot),
            settle: settle));

/// Opens the join flow from the start card.
Future<void> _startJoin(WidgetTester tester) async {
  final join = find.widgetWithText(OutlinedButton, 'Connect this device');
  await tester.ensureVisible(join);
  await tester.tap(join);
  await tester.pumpAndSettle();
  await _focusFlow(tester);
}

/// The Android-only camera screen, pushed from the Devices section as the app
/// does, over [hardware].
Future<void> _scanner(
    WidgetTester tester, Size size, ScannerPlatform hardware) async {
  final previous = CameraPlatform.instance;
  CameraPlatform.instance = hardware;
  addTearDown(() {
    CameraPlatform.instance = previous;
    hardware.frames.close();
  });
  await _devices(
      tester, size, ScriptableDeviceLink(snapshot: _snapshot(canJoin: true)));
  Navigator.of(tester.element(find.byType(DevicesSettingsSection)))
      .push(MaterialPageRoute<String>(builder: (_) => const DeviceQrScanner()));
  await tester.pumpAndSettle();
}

final List<FigmaScene> deviceScenes = [
  FigmaScene('devices-loading', 'Devices / Section / Loading',
      (tester, size) async {
    final commands = ScriptableDeviceLink()..hold(DeviceLinkMethod.snapshot);
    await _devices(tester, size, commands, settle: false);
  }),
  FigmaScene('devices-load-error', 'Devices / Section / Load error',
      (tester, size) async {
    final commands = ScriptableDeviceLink()
      ..buildError = const DeviceLinkError(
          kind: DeviceLinkErrorKind.storage, message: 'locked');
    await _devices(tester, size, commands);
  }),
  _state('devices-new', 'Devices / Section / Only this device',
      _snapshot(canJoin: true)),
  _state('devices-list', 'Devices / Section / Linked devices',
      _snapshot(devices: [_own, _laptop, _phone])),
  FigmaScene('devices-remove-confirm', 'Devices / Remove / Confirm dialog',
      (tester, size) async {
    await _devices(tester, size,
        ScriptableDeviceLink(snapshot: _snapshot(devices: [_own, _laptop])));
    await tester.tap(find.byTooltip('Remove device'));
    await tester.pumpAndSettle();
  }),
  _state(
      'devices-removal-status',
      'Devices / Remove / Removal pending and applied',
      _snapshot(devices: [
        _own,
        _laptop
      ], revocations: [
        DeviceRevocationStatus(
            device: _phone, state: DeviceRevocationState.pending),
        DeviceRevocationStatus(
            device: _device('Old ThinkPad', '3b0e8d14'),
            state: DeviceRevocationState.applied),
      ])),
  _state('devices-revoked', 'Devices / Section / This device was removed',
      _snapshot(revoked: true, canJoin: true)),
  FigmaScene('link-starting', 'Devices / Link / Creating QR (busy)',
      (tester, size) async {
    final commands = ScriptableDeviceLink(snapshot: _snapshot(canJoin: true))
      ..hold(DeviceLinkMethod.beginLink);
    await _devices(tester, size, commands);
    final create = find.text('Create linking QR');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await frames(tester);
  }),
  _state(
      'link-qr',
      'Devices / Link / Showing QR',
      _snapshot(
          role: DeviceLinkRole.authorizing, phase: DeviceLinkPhase.showingQr)),
  FigmaScene('link-qr-copied', 'Devices / Link / Link copied toast',
      (tester, size) async {
    captureClipboard(tester);
    await _devices(
        tester,
        size,
        ScriptableDeviceLink(
            snapshot: _snapshot(
                role: DeviceLinkRole.authorizing,
                phase: DeviceLinkPhase.showingQr)));
    final copy = find.text('Copy link');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await frames(tester, 10);
  }),
  _state(
      'link-connecting',
      'Devices / Link / Connecting',
      _snapshot(
          role: DeviceLinkRole.authorizing, phase: DeviceLinkPhase.connecting),
      settle: false),
  _state(
      'link-approval',
      'Devices / Link / Enter confirmation code',
      _snapshot(
          role: DeviceLinkRole.authorizing,
          phase: DeviceLinkPhase.awaitingApproval,
          pending: _laptop)),
  _state(
      'link-delivering',
      'Devices / Link / Delivering chats',
      _snapshot(
          role: DeviceLinkRole.authorizing,
          phase: DeviceLinkPhase.delivering,
          pending: _laptop),
      settle: false),
  _state('link-linked', 'Devices / Link / Linked',
      _snapshot(phase: DeviceLinkPhase.linked, devices: [_own, _laptop])),
  _state(
      'link-failed',
      'Devices / Link / Failed (code mismatch)',
      _snapshot(
          role: DeviceLinkRole.authorizing,
          phase: DeviceLinkPhase.failed,
          error: DeviceLinkErrorKind.codeMismatch)),
  FigmaScene('devices-refresh-error', 'Devices / Section / Refresh failed',
      (tester, size) async {
    final commands = ScriptableDeviceLink(snapshot: _snapshot(canJoin: true));
    await _devices(tester, size, commands);
    commands.buildError = const DeviceLinkError(
        kind: DeviceLinkErrorKind.unavailable, message: 'offline');
    await ProviderScope.containerOf(
            tester.element(find.byType(DevicesSettingsSection)))
        .read(deviceLinkProvider.notifier)
        .refresh();
    await tester.pumpAndSettle();
  }),
  FigmaScene('join-import', 'Devices / Join / Import QR or link',
      (tester, size) async {
    await _devices(
        tester, size, ScriptableDeviceLink(snapshot: _snapshot(canJoin: true)));
    await _startJoin(tester);
  }),
  FigmaScene('join-invalid', 'Devices / Join / Invalid link',
      (tester, size) async {
    final commands = ScriptableDeviceLink(snapshot: _snapshot(canJoin: true))
      ..actionError = const DeviceLinkError(
          kind: DeviceLinkErrorKind.invalidQr, message: 'invalid');
    await _devices(tester, size, commands);
    await _startJoin(tester);
    await tester.enterText(find.byType(TextField), 'mosh://device-link/eyJ2');
    await tester.tap(find.byTooltip('Connect'));
    await tester.pumpAndSettle();
  }),
  FigmaScene(
      'join-import-android', 'Devices / Join / Import with camera (Android)',
      devices: [FigmaDevice.mobile],
      note: 'The camera button is gated on dart:io Platform.isAndroid, so '
          'the flow card is pushed as its own page inside the app.',
      (tester, size) async {
    await _devices(
        tester, size, ScriptableDeviceLink(snapshot: _snapshot(canJoin: true)));
    Navigator.of(tester.element(find.byType(DevicesSettingsSection)))
        .push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                  backgroundColor: MoshColors.bg0,
                  appBar: AppBar(title: const Text('Settings')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    child: DeviceLinkFlow(
                      snapshot: _snapshot(canJoin: true),
                      role: DeviceLinkRole.joining,
                      busy: false,
                      onApprove: (_) {},
                      onCancel: () {},
                      importForm: DeviceLinkImportForm(
                          busy: false,
                          onSubmit: (_) {},
                          onImage: () {},
                          onScan: () {}),
                    ),
                  ),
                )));
    await tester.pumpAndSettle();
  }),
  FigmaScene(
      'join-scanner',
      'Devices / Scanner / Camera open',
      devices: [FigmaDevice.mobile],
      (tester, size) => _scanner(tester, size, ScannerPlatform())),
  FigmaScene(
      'join-scanner-denied',
      'Devices / Scanner / Camera denied',
      devices: [FigmaDevice.mobile],
      (tester, size) => _scanner(
          tester, size, ScannerPlatform(errorCode: 'CameraAccessDenied'))),
  FigmaScene(
      'join-scanner-unavailable',
      'Devices / Scanner / No camera',
      devices: [FigmaDevice.mobile],
      (tester, size) =>
          _scanner(tester, size, ScannerPlatform(cameras: const []))),
  _state(
      'join-confirmation',
      'Devices / Join / Show confirmation code',
      _snapshot(
          role: DeviceLinkRole.joining,
          phase: DeviceLinkPhase.awaitingConfirmation,
          canJoin: true)),
  _state(
      'join-connecting',
      'Devices / Join / Connecting',
      _snapshot(
          role: DeviceLinkRole.joining,
          phase: DeviceLinkPhase.connecting,
          canJoin: true),
      settle: false),
];
