import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/settings/settings_toggle_card.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/state/gateway_provider.dart' show bridgeFacadeProvider;

import 'async_switch_tile.dart';

/// A switch row bound to the bridge's `readReceiptsEnabled` /
/// `setReadReceiptsEnabled` mirrors (ADR 0025: 1:1 facade calls, not the
/// Gateway conversation seam).
class ReadReceiptsToggle extends ConsumerWidget {
  const ReadReceiptsToggle({super.key, this.bridge});

  /// The facade to read/write through. Defaults to the provider so tests
  /// can hand a ScriptableBridge.
  final BridgeFacade? bridge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final BridgeFacade facade = bridge ?? ref.read(bridgeFacadeProvider);
    return SettingsToggleCard(
      key: const PageStorageKey('privacy-read-receipt-details'),
      detailsTitle: l.settingsReadReceiptsDetailsTitle,
      details: l.settingsReadReceiptsDetails,
      toggle: AsyncSwitchTile(
        secondary: const SettingsIcon(Icons.done_all),
        title: l.settingsReadReceiptsTitle,
        subtitle: l.settingsReadReceiptsSubtitle,
        read: facade.readReceiptsEnabled,
        write: (enabled) => facade.setReadReceiptsEnabled(enabled: enabled),
      ),
    );
  }
}
