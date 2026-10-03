import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

import '../../support/first_run.dart';
import '../../support/first_run_preview.dart';
import '../../support/scriptable_bridge.dart';

const _ethernet = NetworkInterfaceInfo(
    name: 'Ethernet',
    description: '',
    index: 1,
    ipv4: '192.168.1.5',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: true);

FirstRunHarness _harness() => FirstRunHarness(
    profile:
        const FirstRunProfile(displayName: 'Juno', step: SetupStep.network),
    bridge: ScriptableBridge()..seedInterfaces([_ethernet]));

Future<void> _chooseEthernet(WidgetTester tester) async {
  await tapSetup(tester, 'Automatic · system connection');
  await tapSetup(tester, 'Ethernet - 192.168.1.5');
}

void main() {
  testWidgets('automatic routing never writes bypass consent or relaunches',
      (tester) async {
    final harness = _harness();
    await harness.pump(tester);
    await tapSetup(tester, 'Save and finish');
    expect(harness.bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('Windows saves completion before starting the replacement',
      (tester) async {
    final harness = _harness();
    final events = <String>[];
    final relauncher = DesktopAppRelauncher(
        arguments: const [],
        executable: 'mosh.exe',
        isWindows: () => true,
        start: (executable, _, __) async {
          expect(harness.store.profile!.completed, isTrue);
          expect(executable, 'mosh.exe');
          events.add('start');
        },
        terminate: (_) => events.add('exit'));
    await harness.pump(tester, relauncher: relauncher);
    await _chooseEthernet(tester);
    expect(find.textContaining('outside your VPN'), findsOneWidget);
    await tapSetup(tester, 'Save and restart');
    expect(
        harness.bridge
            .lastCall(BridgeMethod.setVpnBypassConsent)!
            .arg<String>('interfaceName'),
        'Ethernet');
    expect(events, ['start', 'exit']);
  });

  testWidgets('unsupported relaunch explains manual restart before chats',
      (tester) async {
    final harness = _harness();
    await harness.pump(tester);
    await _chooseEthernet(tester);
    await tapSetup(tester, 'Save and finish');
    expect(find.text('Restart Mosh to apply the connection'), findsOneWidget);
    expect(harness.store.profile!.completed, isTrue);
    expect(find.byType(SessionsScreen), findsNothing);
    await tapSetup(tester, 'Understood');
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('failed bypass write keeps setup open and can retry',
      (tester) async {
    final harness = _harness()
      ..bridge.failNext(BridgeMethod.setVpnBypassConsent);
    await harness.pump(tester);
    await _chooseEthernet(tester);
    await tapSetup(tester, 'Save and finish');
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(harness.store.profile!.completed, isFalse);
    await tapSetup(tester, 'Save and finish');
    await tapSetup(tester, 'Understood');
    expect(harness.store.profile!.completed, isTrue);
  });

  testWidgets('restart failure retains the saved choice and enables retry',
      (tester) async {
    final harness = _harness();
    var fail = true;
    final relauncher = DesktopAppRelauncher(
        arguments: const [],
        executable: 'mosh.exe',
        isWindows: () => true,
        start: (_, __, ___) async {
          if (fail) throw StateError('restart');
        },
        terminate: (_) {});
    await harness.pump(tester, relauncher: relauncher);
    await _chooseEthernet(tester);
    await tapSetup(tester, 'Save and restart');
    expect(find.textContaining('could not restart'), findsOneWidget);
    expect(harness.store.profile!.completed, isTrue);
    expect(find.byType(SessionsScreen), findsNothing);
    fail = false;
    await tapSetup(tester, 'Save and restart');
    expect(find.byType(SessionsScreen), findsOneWidget);
  });

  testWidgets('network read failure recovers without changing consent',
      (tester) async {
    final harness = _harness()..bridge.failNext(BridgeMethod.listInterfaces);
    await harness.pump(tester);
    expect(find.text('Could not read network state'), findsOneWidget);
    await tapSetup(tester, 'Retry');
    expect(find.text('Automatic · system connection'), findsOneWidget);
    expect(harness.bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
  });

  testWidgets('resizing preserves the selected adapter and bypass explanation',
      (tester) async {
    await prepareSetupPreview(tester);
    final harness = _harness();
    await harness.pump(tester);
    await _chooseEthernet(tester);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(find.text('Ethernet - 192.168.1.5'), findsOneWidget);
    expect(find.textContaining('outside your VPN'), findsOneWidget);
    await saveSetupPreview(tester, 'first-run-network-bypass-small');
    await tester.ensureVisible(find.text('Save and finish'));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 680);
    await tester.pumpAndSettle();
    await tapSetup(tester, 'Save and finish');
    expect(
        harness.bridge
            .lastCall(BridgeMethod.setVpnBypassConsent)!
            .arg<String>('interfaceName'),
        'Ethernet');
    await tapSetup(tester, 'Understood');
    expect(harness.store.profile!.completed, isTrue);
  });

  testWidgets('unavailable saved adapter must be replaced before finishing',
      (tester) async {
    final harness = _harness()
      ..bridge.seedVpnConsent(
          const VpnBypassConsent(interface_: 'Missing', index: 2));
    await harness.pump(tester);
    expect(find.text('Missing · unavailable'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save and finish'))
            .onPressed,
        isNull);
    await tapSetup(tester, 'Missing · unavailable');
    await tapSetup(tester, 'Automatic · system connection');
    await tapSetup(tester, 'Save and finish');
    await tapSetup(tester, 'Understood');
    expect(
        harness.bridge
            .lastCall(BridgeMethod.setVpnBypassConsent)!
            .arg<String?>('interfaceName'),
        isNull);
  });

  testWidgets('Back and Continue keep the unsaved adapter selection',
      (tester) async {
    final harness = _harness();
    await harness.pump(tester);
    await _chooseEthernet(tester);
    await tapSetup(tester, 'Back');
    await tapSetup(tester, 'This is my first device');
    expect(find.text('Ethernet - 192.168.1.5'), findsOneWidget);
    expect(find.textContaining('outside your VPN'), findsOneWidget);
    expect(harness.bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
    expect(harness.bridge.countOf(BridgeMethod.listInterfaces), 1);
  });

  testWidgets('detected VPN is explained without silently enabling bypass',
      (tester) async {
    final harness = _harness()
      ..bridge.seedVpnDetection(const VpnDetection(
          vpnLikely: true,
          suspectInterfaces: ['Tunnel'],
          vpnOwnsDefaultRoute: true));
    await harness.pump(tester);
    expect(find.text('Your VPN currently carries the default network route.'),
        findsOneWidget);
    await tapSetup(tester, 'Save and finish');
    expect(harness.bridge.countOf(BridgeMethod.setVpnBypassConsent), 0);
    expect(find.text('Route around the VPN'), findsNothing);
  });
}
