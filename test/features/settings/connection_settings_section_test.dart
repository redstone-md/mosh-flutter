import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/connection_settings_section.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/moss_runtime.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/gateway_snapshots.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

Future<void> _pump(WidgetTester tester, ScriptableBridge bridge,
    {Widget? section, double textScale = 1, bool settle = true}) async {
  final container = ProviderContainer(
    overrides: [bridgeFacadeProvider.overrideWithValue(bridge)],
    retry: (_, __) => null,
  );
  addTearDown(container.dispose);
  await pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme(),
        child: Builder(
            builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(
                      body: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: section ?? const ConnectionSettingsSection())),
                )),
      ),
      container: container,
      settle: settle);
}

Future<void> _open(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

ScriptableBridge _bridge() => ScriptableBridge()
  ..seedInterfaces([
    const NetworkInterfaceInfo(
        name: 'Ethernet',
        description: '',
        index: 1,
        ipv4: '192.168.1.5',
        isUp: true,
        isLoopback: false,
        isVirtual: false,
        isVpn: false,
        isDefaultRoute: true)
  ]);

void main() {
  testWidgets(
      'disclosures load on demand and discovery has public metadata copy',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge);
    expect(find.text('Automatic discovery'), findsOneWidget);
    expect(find.textContaining('public trackers'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listInterfaces), 0);
    expect(bridge.countOf(BridgeMethod.nativeRuntimeStatus), 0);
    expect(bridge.countOf(BridgeMethod.mossLibraryInfo), 0);
    await _open(tester, 'How it works');
    expect(find.textContaining('establishes a route automatically'),
        findsOneWidget);
    await _open(tester, 'If a VPN gets in the way');
    expect(bridge.countOf(BridgeMethod.listInterfaces), 1);
    expect(find.text('Bind'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.nativeRuntimeStatus), 0);
  });

  testWidgets(
      'unsupported relaunch saves and shows manual restart after collapse',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge);
    await _open(tester, 'If a VPN gets in the way');
    expect(find.textContaining('After saving, close Mosh completely'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Bind'));
    await tester.tap(find.text('Bind'));
    await tester.pumpAndSettle();
    expect(
        bridge
            .lastCall(BridgeMethod.setVpnBypassConsent)
            ?.arg<String?>('interfaceName'),
        'Ethernet');
    expect(find.textContaining('Saved. Close Mosh completely'), findsOneWidget);
    await _open(tester, 'If a VPN gets in the way');
    await _open(tester, 'If a VPN gets in the way');
    expect(find.textContaining('Saved. Close Mosh completely'), findsOneWidget);
    expect(bridge.countOf(BridgeMethod.listInterfaces), 1);
  });

  testWidgets('diagnostics show runtime values and refresh both reads',
      (tester) async {
    final bridge = _bridge()
      ..seedMossLibraryInfo(const MossLibraryInfo(
          version: '0.9.0', logPath: '/data/mosh/field.log'));
    await _pump(tester, bridge);
    await _open(tester, 'Diagnostics');
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('moss.dll'), findsOneWidget);
    expect(find.text('dynamic'), findsOneWidget);
    expect(find.text('0.9.0'), findsOneWidget);
    expect(find.text('/data/mosh/field.log'), findsOneWidget);
    expect(
        bridge
            .lastCall(BridgeMethod.mossLibraryInfo)
            ?.arg<String?>('peerMossId'),
        isNull);
    bridge.seedMossLibraryInfo(const MossLibraryInfo(version: 'unknown'));
    await _open(tester, 'Refresh status');
    expect(find.text('unknown'), findsOneWidget);
    expect(find.text('/data/mosh/field.log'), findsNothing);
    expect(bridge.countOf(BridgeMethod.nativeRuntimeStatus), 2);
    expect(bridge.countOf(BridgeMethod.mossLibraryInfo), 2);
  });

  testWidgets('unavailable library stays unavailable rather than Connected',
      (tester) async {
    final status = cannedNativeRuntimeStatus();
    final bridge = _bridge()
      ..seedNativeRuntimeStatus(NativeRuntimeStatus(
          moss: const MossRuntimeStatus(
              linkMode: 'dynamic',
              libraryName: 'libmoss.so',
              requiredSymbols: [],
              available: false,
              checkedPaths: []),
          secureStorage: status.secureStorage,
          persistence: status.persistence,
          openmlsSmoke: status.openmlsSmoke,
          openmlsRoundtrip: status.openmlsRoundtrip));
    await _pump(tester, bridge);
    await _open(tester, 'Diagnostics');
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Available'), findsNothing);
    expect(find.textContaining('local engine details'), findsOneWidget);
  });

  testWidgets('failed diagnostics can be retried without a native exception',
      (tester) async {
    final bridge = _bridge()
      ..failNext(BridgeMethod.nativeRuntimeStatus)
      ..failNext(BridgeMethod.mossLibraryInfo);
    await _pump(tester, bridge);
    await _open(tester, 'Diagnostics');
    expect(
        find.textContaining('Could not read engine details'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    await _open(tester, 'Refresh status');
    expect(find.text('Available'), findsOneWidget);
    expect(find.textContaining('Could not read engine details'), findsNothing);
  });

  testWidgets('library error preserves runtime values and allows retry',
      (tester) async {
    final bridge = _bridge()..failNext(BridgeMethod.mossLibraryInfo);
    await _pump(tester, bridge);
    await _open(tester, 'Diagnostics');
    expect(find.text('Available'), findsOneWidget);
    expect(
        find.textContaining('Could not read engine details'), findsOneWidget);
    await _open(tester, 'Refresh status');
    expect(find.text('dev'), findsOneWidget);
  });

  testWidgets('pending diagnostics disable refresh until both reads finish',
      (tester) async {
    final bridge = _bridge()
      ..hold(BridgeMethod.nativeRuntimeStatus)
      ..hold(BridgeMethod.mossLibraryInfo);
    await _pump(tester, bridge);
    await tester.tap(find.text('Diagnostics'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reading engine details…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Refresh status'))
            .onPressed,
        isNull);
    bridge.release(BridgeMethod.nativeRuntimeStatus);
    await tester.pumpAndSettle();
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Reading engine details…'), findsOneWidget);
    bridge.release(BridgeMethod.mossLibraryInfo);
    await tester.pumpAndSettle();
    expect(find.text('Reading engine details…'), findsNothing);
  });

  testWidgets('read receipts live in Privacy and retain the real write seam',
      (tester) async {
    final bridge = _bridge();
    await _pump(tester, bridge,
        section: const SettingsContent(
            section: SettingsSection.privacy, wide: false));
    expect(find.text('Read receipts'), findsOneWidget);
    final toggle = find.byType(SwitchListTile).last;
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
        bridge
            .lastCall(BridgeMethod.setReadReceiptsEnabled)
            ?.arg<bool>('enabled'),
        isTrue);
  });

  testWidgets('320px with enlarged text scrolls both expanded blocks',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = _bridge();
    await _pump(tester, bridge, textScale: 2);
    await _open(tester, 'If a VPN gets in the way');
    await _open(tester, 'Diagnostics');
    await tester.ensureVisible(find.text('Refresh status'));
    expect(find.text('Available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
