import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/crypto_notice_banner.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show DmDeviceRevocationState;

class DmRevocationBanner extends StatelessWidget {
  const DmRevocationBanner({required this.state, super.key});
  final DmDeviceRevocationState? state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final copy = switch (state) {
      DmDeviceRevocationState.pending => (
          l.dmRemovalPendingTitle,
          l.dmRemovalPendingBody
        ),
      DmDeviceRevocationState.revoked => (
          l.dmDeviceRevokedTitle,
          l.dmDeviceRevokedBody
        ),
      DmDeviceRevocationState.applied || null => null,
    };
    if (copy == null) return const SizedBox.shrink();
    return CryptoNoticeBanner(
        icon: Icons.link_off,
        title: copy.$1,
        body: copy.$2,
        accent: MoshColors.info);
  }
}
