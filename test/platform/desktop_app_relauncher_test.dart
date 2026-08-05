import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/vpn/vpn_consent_overlay.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  group('DesktopAppRelauncher', () {
    test('starts the current executable with current arguments', () async {
      String? executable;
      List<String>? arguments;
      ProcessStartMode? mode;
      int? exitCode;
      final relauncher = DesktopAppRelauncher(
        executable: r'C:\Program Files\Mosh\mosh.exe',
        arguments: const ['mosh://invite?mesh=7x9v', '--profile', 'work'],
        isWindows: () => true,
        start: (path, args, startMode) async {
          executable = path;
          arguments = args;
          mode = startMode;
        },
        terminate: (code) => exitCode = code,
      );

      await relauncher.relaunch();

      expect(executable, r'C:\Program Files\Mosh\mosh.exe');
      expect(arguments, ['mosh://invite?mesh=7x9v', '--profile', 'work']);
      expect(mode, ProcessStartMode.detached);
      expect(exitCode, 0);
    });

    test('terminates only after the replacement spawn completes', () async {
      final events = <String>[];
      final spawn = Completer<void>();
      final relauncher = DesktopAppRelauncher(
        executable: 'mosh',
        arguments: const [],
        isWindows: () => true,
        start: (_, __, ___) {
          events.add('spawn');
          return spawn.future;
        },
        terminate: (_) => events.add('terminate'),
      );

      final pending = relauncher.relaunch();
      expect(events, ['spawn']);

      spawn.complete();
      await pending;

      expect(events, ['spawn', 'terminate']);
    });

    test('propagates spawn failure without terminating', () async {
      var terminateCount = 0;
      final relauncher = DesktopAppRelauncher(
        executable: 'mosh',
        arguments: const [],
        isWindows: () => true,
        start: (_, __, ___) async {
          throw StateError('spawn failed');
        },
        terminate: (_) => terminateCount++,
      );

      await expectLater(relauncher.relaunch(), throwsStateError);
      expect(terminateCount, 0);
    });

    test('does not spawn or terminate on an unsupported platform', () async {
      var spawnCount = 0;
      var terminateCount = 0;
      final relauncher = DesktopAppRelauncher(
        executable: 'mosh',
        arguments: const [],
        isWindows: () => false,
        start: (_, __, ___) async => spawnCount++,
        terminate: (_) => terminateCount++,
      );

      await relauncher.relaunch();

      expect(spawnCount, 0);
      expect(terminateCount, 0);
    });
  });

  group('production relaunch wiring', () {
    testWidgets('VPN consent overlay invokes the scoped relauncher',
        (tester) async {
      final gateway = _ConsentGateway(
        detection: _ownsDefault(),
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      final relauncher = _RecordingRelauncher();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [gatewayProvider.overrideWithValue(gateway)],
          child: DesktopAppRelauncherScope(
            relauncher: relauncher.value,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: VpnConsentOverlay(child: const SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Route around the VPN'));
      await tester.pumpAndSettle();

      expect(relauncher.events, ['spawn', 'terminate']);
    });

    testWidgets(
        'OnboardMenu passes the scoped relauncher to BindInterfaceField',
        (tester) async {
      final gateway = _BindGateway(
        interfaces: [_iface(name: 'eth0', ipv4: '192.168.1.5')],
      );
      final relauncher = _RecordingRelauncher();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [gatewayProvider.overrideWithValue(gateway)],
          child: DesktopAppRelauncherScope(
            relauncher: relauncher.value,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: OnboardMenu(
                    onPickChat: () {},
                    onPickGroup: () {},
                    onPickChannel: () {},
                    onPickJoin: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final advanced = find.text('Advanced connection settings');
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      final bind = find.text('Bind');
      await tester.ensureVisible(bind);
      await tester.tap(bind);
      await tester.pumpAndSettle();

      expect(relauncher.events, ['spawn', 'terminate']);
    });
  });
}

class _RecordingRelauncher {
  final events = <String>[];

  late final value = DesktopAppRelauncher(
    executable: 'mosh',
    arguments: const [],
    isWindows: () => true,
    start: (_, __, ___) async => events.add('spawn'),
    terminate: (_) => events.add('terminate'),
  );
}

class _ConsentGateway implements Gateway {
  final VpnDetection detection;
  final List<NetworkInterfaceInfo> interfaces;

  _ConsentGateway({required this.detection, required this.interfaces});

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() async => null;

  @override
  Future<VpnDetection> detectVpn() async => detection;

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() async => interfaces;

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _BindGateway implements Gateway {
  final List<NetworkInterfaceInfo> interfaces;

  _BindGateway({required this.interfaces});

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() async => interfaces;

  @override
  Future<String?> getBindInterface() async => null;

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

NetworkInterfaceInfo _iface({required String name, required String ipv4}) =>
    NetworkInterfaceInfo(
      name: name,
      description: '',
      index: 0,
      ipv4: ipv4,
      isLoopback: false,
      isUp: true,
      isVirtual: false,
      isVpn: false,
      isDefaultRoute: false,
    );

VpnDetection _ownsDefault() => const VpnDetection(
      vpnLikely: true,
      suspectInterfaces: ['tun0'],
      vpnOwnsDefaultRoute: true,
    );
