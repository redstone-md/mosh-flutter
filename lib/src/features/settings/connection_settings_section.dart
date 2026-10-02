import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/vpn/bind_interface_field.dart';
import 'package:mosh/src/platform/desktop_app_relauncher.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import 'connection_diagnostics.dart';
import 'settings_card.dart';
import 'settings_disclosure.dart';

/// Automatic discovery with opt-in troubleshooting and local diagnostics.
class ConnectionSettingsSection extends ConsumerWidget {
  const ConnectionSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final relauncher = DesktopAppRelauncherScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _discovery(context, l),
        const SizedBox(height: 16),
        SettingsDisclosure(
          icon: Icons.lan_outlined,
          title: l.settingsVpnTitle,
          summary: l.settingsVpnSummary,
          child: BindInterfaceField(
            bridge: ref.watch(bridgeFacadeProvider),
            l: l,
            onAccept: relauncher.relaunch,
            canRelaunch: relauncher.supported,
          ),
        ),
        const SizedBox(height: 16),
        SettingsDisclosure(
          icon: Icons.info_outline,
          title: l.diagnosticsDiagnostics,
          summary: l.settingsConnectionDiagnosticsSummary,
          child: const ConnectionDiagnostics(),
        ),
      ],
    );
  }

  Widget _discovery(BuildContext context, AppLocalizations l) => SettingsCard(
        icon: Icons.radar,
        title: l.settingsDiscoveryTitle,
        hint: l.settingsDiscoveryHint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.settingsDiscoveryBody,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text(l.settingsDiscoveryDetailsTitle,
                  style: Theme.of(context).textTheme.bodySmall),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              shape: const Border(),
              collapsedShape: const Border(),
              visualDensity: VisualDensity.standard,
              children: [
                Text(l.settingsDiscoveryDetails,
                    style: Theme.of(context).textTheme.bodySmall)
              ],
            ),
          ],
        ),
      );
}
