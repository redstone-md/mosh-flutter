import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/settings/settings_card.dart';

/// Choose the installation's role before entering the sequential linking flow.
class DeviceLinkStartActions extends StatelessWidget {
  const DeviceLinkStartActions({
    super.key,
    required this.canJoin,
    required this.revoked,
    required this.onAuthorize,
    required this.onJoin,
  });

  final bool canJoin;
  final bool revoked;
  final VoidCallback? onAuthorize;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!revoked) ...[
        SettingsCard(
          icon: Icons.qr_code_2,
          title: l.deviceLinkLinkOther,
          hint: l.deviceLinkHelp,
          child: FilledButton.icon(
            onPressed: onAuthorize,
            icon: const Icon(Icons.add_link, size: 20),
            label: Text(l.deviceLinkJoin),
          ),
        ),
        const SizedBox(height: 16),
      ],
      SettingsCard(
        icon: Icons.devices_outlined,
        title: l.deviceLinkConnectThis,
        hint: revoked
            ? l.deviceLinkRevokedBody
            : canJoin
                ? l.deviceLinkJoinHelp
                : l.deviceLinkIneligible,
        child: OutlinedButton.icon(
          onPressed: canJoin ? onJoin : null,
          icon: const Icon(Icons.qr_code_scanner, size: 20),
          label:
              Text(revoked ? l.deviceLinkFreshJoin : l.deviceLinkConnectThis),
        ),
      ),
    ]);
  }
}
