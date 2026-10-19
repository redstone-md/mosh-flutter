import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'plus_provider.dart';
import 'plus_state.dart';
import 'plus_checkout.dart';
import 'plus_membership_status.dart';
import 'plus_recovery_panel.dart';

class PlusMainnetSettings extends ConsumerWidget {
  const PlusMainnetSettings(
      {super.key, required this.value, required this.config});
  final PlusState value;
  final PlusConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final snapshot = value.snapshot;
    final controller = ref.read(plusProvider.notifier);
    final recoveryIds =
        snapshot.recovery?.orders.map((order) => order.id).toSet() ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (snapshot.active)
        PlusMembershipStatus(
            snapshot: snapshot,
            busy: value.busy,
            onVisibility: controller.visibility),
      if (!snapshot.active && snapshot.nextActiveFromMs != null)
        Text(l.plusNextPeriod(formatPlusDate(snapshot.nextActiveFromMs!))),
      if (snapshot.reservedUntilMs != null &&
          snapshot.reservedUntilMs! > (snapshot.expiresAtMs ?? BigInt.zero))
        Text(l.plusReservedThrough(formatPlusDate(snapshot.reservedUntilMs!))),
      for (final order in snapshot.orders)
        if (snapshot.unissuedOrderIds.contains(order.id) &&
            order.accessToken != null &&
            !recoveryIds.contains(order.id))
          PlusPendingPayment(
              order: order, busy: value.busy, onRefresh: controller.refresh),
      if (config.canPurchase) ...[
        if (snapshot.checkoutIntent != null)
          TextButton(
              onPressed: value.busy ? null : controller.cancelCheckout,
              child: Text(l.plusCancelSetup)),
        if (!snapshot.checkoutReady) Text(l.plusWaitingSync),
        PlusNewPayment(
            busy: value.busy,
            onPurchase: controller.purchase,
            ready: snapshot.checkoutReady,
            renewal: snapshot.active,
            onSelectPurchase: controller.purchase),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: value.busy || !snapshot.checkoutReady
                ? null
                : controller.recover,
            icon: const Icon(Icons.restore),
            label: Text(l.plusRecover)),
      ] else
        Text(l.plusUnavailable),
      if (snapshot.recovery case final session?)
        PlusRecoveryPanel(
            session: session, busy: value.busy, onRefresh: controller.refresh),
      const SizedBox(height: 12),
      Text(l.plusMainnetPrivacy),
    ]);
  }
}
