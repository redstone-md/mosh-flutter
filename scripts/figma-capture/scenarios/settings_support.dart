// Mounting helpers for the settings Figma scenes: the real MoshApp at
// /settings with every seam the settings pages read scripted.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/main.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/settings/app_package_info_provider.dart';
import 'package:mosh/src/features/settings/app_release_provider.dart';
import 'package:mosh/src/features/settings/app_update_install.dart';
import 'package:mosh/src/features/settings/settings_nav.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/native_call/types.dart' show Device;
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/state/camera_device_picks_provider.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:record/record.dart' show InputDevice;

import '../../../test/support/first_run.dart';
import '../../../test/support/scriptable_bridge.dart';
import '../../../test/support/scriptable_gateway.dart';
import '../../../test/support/settings.dart';
import 'harness.dart';

final l10n = lookupAppLocalizations(const Locale('en'));

PackageInfo package() => PackageInfo(
    appName: 'Mosh',
    packageName: 'app.mosh',
    version: '0.21.4',
    buildNumber: '214');

const ethernet = NetworkInterfaceInfo(
    name: 'Ethernet',
    description: 'Intel(R) Ethernet Connection I219-V',
    index: 4,
    ipv4: '192.168.1.24',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: false);
const wifi = NetworkInterfaceInfo(
    name: 'Wi-Fi',
    description: 'Intel(R) Wi-Fi 6 AX201',
    index: 7,
    ipv4: '192.168.1.31',
    isUp: true,
    isLoopback: false,
    isVirtual: false,
    isVpn: false,
    isDefaultRoute: false);
const vpnTunnel = NetworkInterfaceInfo(
    name: 'WireGuard',
    description: 'WireGuard Tunnel',
    index: 12,
    ipv4: '10.64.0.2',
    isUp: true,
    isLoopback: false,
    isVirtual: true,
    isVpn: true,
    isDefaultRoute: true);

ScriptableBridge settingsBridge([ScriptableGateway? gateway]) =>
    ScriptableBridge(conversations: gateway?.conversations)
      ..seedInterfaces(const [vpnTunnel, ethernet, wifi]);

/// The defaults every settings capture shares; [overrides] replace them by
/// provider, so a scene names only what it changes.
List<Override> _defaults({
  required ScriptableGateway gateway,
  required ScriptableBridge bridge,
  MemoryAudioPicks? picks,
  RecordingSettingsRingtone? ringtone,
  Future<List<InputDevice>> Function()? inputs,
}) =>
    [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      ...settingsAudioOverrides(
          picks: picks,
          ringtone: ringtone ?? RecordingSettingsRingtone(),
          inputs: inputs),
      cameraDevicesProvider.overrideWith((ref) async => const [
            Device(id: 'cam-1', name: 'Logitech C920 HD Pro', stable: true),
          ]),
      defaultCameraProvider.overrideWith(MemoryDefaultCamera.new),
      firstRunStoreProvider.overrideWithValue(MemoryFirstRunStore(
          const FirstRunProfile(displayName: 'Alex Rivera', completed: true))),
      appPackageInfoProvider.overrideWith((ref) async => package()),
      updateCheckProvider.overrideWith((ref) async => null),
      hostPlatformProvider.overrideWithValue(HostPlatform.other),
      ...figmaLocale,
    ];

/// Pumps MoshApp at [location] (settings by default) with the defaults above
/// plus [overrides], and opens [section] through the settings navigation.
Future<void> mountSettings(
  WidgetTester tester,
  Size size, {
  SettingsSection? section,
  String location = AppRoutes.settings,
  ScriptableGateway? gateway,
  ScriptableBridge? bridge,
  MemoryAudioPicks? picks,
  RecordingSettingsRingtone? ringtone,
  Future<List<InputDevice>> Function()? inputs,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  final g = gateway ?? ScriptableGateway();
  final b = bridge ?? settingsBridge(g);
  figmaSurface(tester, size);
  appRouter.go(location);
  final defaults = _defaults(
      gateway: g, bridge: b, picks: picks, ringtone: ringtone, inputs: inputs);
  // A container rejects two overrides of one provider; a scene's own wins.
  // ignore: invalid_use_of_visible_for_testing_member
  Object origin(Override o) => o.origin;
  final replaced = overrides.map(origin).toSet();
  await tester.pumpWidget(ProviderScope(
    retry: (_, __) => null,
    overrides: [
      for (final o in defaults)
        if (!replaced.contains(origin(o))) o,
      ...overrides,
    ],
    child: const MoshApp(),
  ));
  await tester.pumpAndSettle();
  if (section != null) await openSection(tester, section, settle: settle);
}

/// Taps [section] in the sidebar (wide) or the section list (narrow).
Future<void> openSection(WidgetTester tester, SettingsSection section,
    {bool settle = true}) async {
  await tester.tap(find.descendant(
      of: find.byType(SettingsNav), matching: find.text(section.label(l10n))));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder,
    {bool settle = true}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Scrolls the settings content so [finder] sits near the top.
Future<void> revealTop(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
}

/// An update run held in one state, so About renders it without I/O.
class FixedInstall extends UpdateInstall {
  FixedInstall(this.fixed);
  final UpdateInstallState fixed;

  @override
  UpdateInstallState build() => fixed;
}

/// A future that never answers: the loading state, held.
Future<T> never<T>() => Completer<T>().future;
