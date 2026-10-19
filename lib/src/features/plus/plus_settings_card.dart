import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/settings/settings_card.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'plus_checkout.dart';
import 'plus_provider.dart';
import 'plus_state.dart';
import 'plus_mainnet_settings.dart';
import 'plus_membership_status.dart';

class PlusSettingsCard extends ConsumerWidget {
  const PlusSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(plusConfigProvider);
    if (!config.enabled) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return SettingsCard(
        icon: Icons.workspace_premium_outlined,
        title: 'Mosh+',
        hint: config.mainnet ? l.plusSupportHint : l.plusPilotHint,
        child: ref.watch(plusProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _retry(l, () => ref.invalidate(plusProvider)),
              data: (value) => _content(ref, value, config, l),
            ));
  }

  Widget _content(
      WidgetRef ref, PlusState value, PlusConfig config, AppLocalizations l) {
    final snapshot = value.snapshot;
    final controller = ref.read(plusProvider.notifier);
    if (config.mainnet) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PlusMainnetSettings(value: value, config: config),
        if (value.error != null) _retry(l, controller.refresh),
      ]);
    }
    final expiry = snapshot.expiresAtMs;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (snapshot.active) ...[
        PlusMembershipStatus(
            snapshot: snapshot,
            busy: value.busy,
            onVisibility: controller.visibility),
      ] else if (snapshot.order case final order? when _pending(order))
        PlusPendingPayment(
            order: order, busy: value.busy, onRefresh: controller.refresh)
      else ...[
        if (expiry != null) Text(l.plusExpired),
        if (config.canPurchase)
          PlusNewPayment(busy: value.busy, onPurchase: controller.purchase)
        else
          Text(l.plusUnavailable),
      ],
      if (value.error != null) _retry(l, controller.refresh),
      const SizedBox(height: 12),
      Text(l.plusPrivacyHint),
    ]);
  }

  bool _pending(PlusOrder order) =>
      order.status == PlusPaymentStatus.awaitingPayment ||
      (order.expiresAtMs?.toInt() ?? 0) > DateTime.now().millisecondsSinceEpoch;

  Widget _retry(AppLocalizations l, VoidCallback retry) => Column(children: [
        Text(l.plusRetryError),
        TextButton(onPressed: retry, child: Text(l.plusRetry))
      ]);
}
