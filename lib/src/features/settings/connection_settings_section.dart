import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'settings_disclosure.dart';

/// Optional adapter override for networks where VPN interferes with discovery.
class ConnectionSettingsSection extends ConsumerWidget {
  const ConnectionSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final relauncher = DesktopAppRelauncherScope.of(context);
    return SettingsDisclosure(
      key: const PageStorageKey('connection-vpn'),
      icon: Icons.lan_outlined,
      title: l.settingsVpnTitle,
      summary: l.settingsVpnSummary,
      child: BindInterfaceField(
        bridge: ref.watch(bridgeFacadeProvider),
        l: l,
        onAccept: relauncher.relaunch,
        canRelaunch: relauncher.supported,
      ),
    );
  }
}
