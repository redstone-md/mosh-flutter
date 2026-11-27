// First-run wizard scenes for the onboarding area: the setup gate, the
// name, device and network steps with their loading, error and dialog states.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/device_link/device_link_provider.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/device_link/types.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../../test/support/first_run.dart';
import '../../../test/support/locale.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_device_link.dart';
import '../../../test/support/scriptable_gateway.dart';
import 'harness.dart';

const _name = 'Maya Chen';
const _link = 'mosh://device-link/7x9v-k2p8-drift';

const _ethernet = NetworkInterfaceInfo(
    name: 'Ethernet',
    description: '',
    index: 1,
    ipv4: '192.168.1.24',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: true);
const _wifi = NetworkInterfaceInfo(
    name: 'Wi-Fi',
    description: '',
    index: 2,
    ipv4: '10.0.0.17',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: false);

/// A store whose read never answers, so the gate stays on its spinner.
class _HangingStore extends FirstRunStore {
  _HangingStore() : super(null);
  @override
  Future<FirstRunProfile?> read() => Completer<FirstRunProfile?>().future;
  @override
  Future<void> write(FirstRunProfile profile) async {}
}

ScriptableBridge _networkBridge() =>
    ScriptableBridge()..seedInterfaces([_ethernet, _wifi]);

/// Windows relaunches itself after a bypass change; [fail] scripts a failure.
DesktopAppRelauncher _windowsRelauncher({bool fail = false}) =>
    DesktopAppRelauncher(
        arguments: const [],
        executable: 'mosh.exe',
        isWindows: () => true,
        start: (_, __, ___) async {
          if (fail) throw StateError('restart');
        },
        terminate: (_) {});

/// Mounts the real app behind the enabled setup gate at [step].
Future<FirstRunHarness> _setup(WidgetTester tester, Size size,
    {SetupStep step = SetupStep.name,
    String name = _name,
    ScriptableBridge? bridge,
    ScriptableDeviceLink? link,
    DesktopAppRelauncher? relauncher,
    bool settle = true}) async {
  final harness = FirstRunHarness(
      profile: FirstRunProfile(displayName: name, step: step),
      bridge: bridge,
      link: link,
      localeStore: MemoryLocalePreferenceStore(const Locale('en')));
  await harness.pump(tester,
      size: size, relauncher: relauncher, settle: settle);
  return harness;
}

Future<void> _openLinkInput(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _link);
  await tester.pumpAndSettle();
}

Future<void> _submitLink(WidgetTester tester) async {
  await _openLinkInput(tester);
  await tester.ensureVisible(find.byTooltip('Connect'));
  await tester.tap(find.byTooltip('Connect'));
}

Future<void> _pickEthernet(WidgetTester tester) async {
  await tapSetup(tester, 'Automatic, system connection');
  await tapSetup(tester, 'Ethernet - 192.168.1.24');
}

ScriptableDeviceLink _linkAt(DeviceLinkPhase phase) => ScriptableDeviceLink(
    snapshot: setupDeviceSnapshot(role: DeviceLinkRole.joining, phase: phase));

final List<FigmaScene> setupScenes = [
  FigmaScene('setup-loading', 'Onboarding / Setup / Loading',
      (tester, size) async {
    final bridge = ScriptableBridge();
    appRouter.go(AppRoutes.sessions);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...figmaLocale,
      firstRunEnabledProvider.overrideWithValue(true),
      firstRunStoreProvider.overrideWithValue(_HangingStore()),
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(
          ScriptableGateway(conversations: bridge.conversations)),
    ], child: const MoshApp()));
    await tester.pump(const Duration(milliseconds: 300));
  }),
  FigmaScene('setup-read-error', 'Onboarding / Setup / Read error',
      (tester, size) async {
    final harness = FirstRunHarness(
        profile: const FirstRunProfile(),
        localeStore: MemoryLocalePreferenceStore(const Locale('en')))
      ..store.readError = const FormatException('corrupt');
    await harness.pump(tester, size: size);
  }),
  FigmaScene('name', 'Onboarding / Name / Empty', (tester, size) async {
    await _setup(tester, size, name: '');
  }),
  FigmaScene('name-required', 'Onboarding / Name / Name required',
      (tester, size) async {
    await _setup(tester, size, name: '');
    await tapSetup(tester, 'Continue');
  }),
  FigmaScene('name-save-error', 'Onboarding / Name / Save error',
      (tester, size) async {
    final harness = await _setup(tester, size, name: '');
    await tester.enterText(find.byType(TextFormField), _name);
    harness.store.writeError = StateError('disk');
    await tapSetup(tester, 'Continue');
  }),
  FigmaScene('device', 'Onboarding / Device / Choose', (tester, size) async {
    await _setup(tester, size, step: SetupStep.device);
  }),
  FigmaScene('device-loading', 'Onboarding / Device / Loading',
      (tester, size) async {
    final link = ScriptableDeviceLink()..hold(DeviceLinkMethod.snapshot);
    await _setup(tester, size,
        step: SetupStep.device, link: link, settle: false);
    await tester.pump(const Duration(milliseconds: 600));
  }),
  FigmaScene('device-link-input', 'Onboarding / Device / Paste link',
      (tester, size) async {
    await _setup(tester, size, step: SetupStep.device);
    await _openLinkInput(tester);
  }),
  FigmaScene('device-link-connecting', 'Onboarding / Device / Connecting',
      (tester, size) async {
    final harness = await _setup(tester, size, step: SetupStep.device);
    harness.link.hold(DeviceLinkMethod.joinLink);
    await _submitLink(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }),
  FigmaScene('device-proof', 'Onboarding / Device / Confirmation code',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.device,
        link: _linkAt(DeviceLinkPhase.awaitingConfirmation));
  }),
  FigmaScene('device-delivering', 'Onboarding / Device / Delivering',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.device,
        link: _linkAt(DeviceLinkPhase.delivering),
        settle: false);
    await tester.pump(const Duration(milliseconds: 600));
  }),
  FigmaScene('device-linked', 'Onboarding / Device / Linked',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.device,
        link: ScriptableDeviceLink(
            snapshot: setupDeviceSnapshot(
                phase: DeviceLinkPhase.linked, canJoin: false, devices: 2)));
  }),
  FigmaScene(
      'device-already-approved', 'Onboarding / Device / Already approved',
      (tester, size) async {
    final harness = await _setup(tester, size,
        step: SetupStep.device,
        link: _linkAt(DeviceLinkPhase.awaitingConfirmation));
    harness.link.snapshotAfterCancel = setupDeviceSnapshot(
        phase: DeviceLinkPhase.failed, canJoin: false, devices: 2);
    await tapSetup(tester, 'Cancel linking and continue independently');
  }),
  FigmaScene('device-cancel-error', 'Onboarding / Device / Cancel failed',
      (tester, size) async {
    final harness = await _setup(tester, size,
        step: SetupStep.device,
        link: _linkAt(DeviceLinkPhase.awaitingConfirmation));
    harness.link.actionError = StateError('cancel');
    await tapSetup(tester, 'Cancel linking and continue independently');
  }),
  FigmaScene('device-read-error', 'Onboarding / Device / Read error',
      (tester, size) async {
    final harness = await _setup(tester, size, step: SetupStep.device);
    harness.link.failNext(DeviceLinkMethod.snapshot);
    await harness.container.read(deviceLinkProvider.notifier).refresh();
    await tester.pumpAndSettle();
  }),
  FigmaScene('network', 'Onboarding / Network / Automatic',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network, bridge: _networkBridge());
  }),
  FigmaScene('network-loading', 'Onboarding / Network / Loading',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge()..hold(BridgeMethod.listInterfaces),
        settle: false);
    await tester.pump(const Duration(milliseconds: 600));
  }),
  FigmaScene('network-picker', 'Onboarding / Network / Adapter menu',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network, bridge: _networkBridge());
    await tapSetup(tester, 'Automatic, system connection');
  }),
  FigmaScene('network-bypass', 'Onboarding / Network / Bypass adapter',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge(),
        relauncher: _windowsRelauncher());
    await _pickEthernet(tester);
  }),
  FigmaScene('network-vpn', 'Onboarding / Network / VPN detected',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge()
          ..seedVpnDetection(const VpnDetection(
              vpnLikely: true,
              suspectInterfaces: ['Tunnel'],
              vpnOwnsDefaultRoute: true)));
  }),
  FigmaScene('network-unavailable', 'Onboarding / Network / Saved adapter gone',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge()
          ..seedVpnConsent(
              const VpnBypassConsent(interface_: 'USB Ethernet', index: 7)));
  }),
  FigmaScene('network-read-error', 'Onboarding / Network / Read error',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge()..failNext(BridgeMethod.listInterfaces));
  }),
  FigmaScene('network-save-error', 'Onboarding / Network / Save error',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge()..failNext(BridgeMethod.setVpnBypassConsent));
    await _pickEthernet(tester);
    await tapSetup(tester, 'Save and finish');
  }),
  FigmaScene('network-restart-dialog', 'Onboarding / Network / Restart dialog',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network, bridge: _networkBridge());
    await _pickEthernet(tester);
    await tapSetup(tester, 'Save and finish');
  }),
  FigmaScene('network-restart-error', 'Onboarding / Network / Restart failed',
      (tester, size) async {
    await _setup(tester, size,
        step: SetupStep.network,
        bridge: _networkBridge(),
        relauncher: _windowsRelauncher(fail: true));
    await _pickEthernet(tester);
    await tapSetup(tester, 'Save and restart');
  }),
];
