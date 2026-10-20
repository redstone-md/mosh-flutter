import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'plus_provider.dart';
import 'plus_catalog.dart';
import 'plus_currency_checkout.dart';
import 'plus_payment_details.dart';

export 'plus_payment_details.dart' show PlusPaymentTerms;

class PlusNewPayment extends ConsumerWidget {
  const PlusNewPayment(
      {super.key,
      required this.busy,
      required this.onPurchase,
      this.onSelectPurchase,
      this.onRecover,
      this.ready = true,
      this.renewal = false});
  final bool busy;
  final VoidCallback onPurchase;
  final ValueChanged<String>? onSelectPurchase;
  final VoidCallback? onRecover;
  final bool ready;
  final bool renewal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final recovery = onRecover == null
        ? null
        : TextButton(
            onPressed: busy || !ready ? null : onRecover,
            child: Text(l.plusRecover));
    return ref.watch(plusCatalogProvider).when(
          loading: () => Column(children: [
            const Center(child: CircularProgressIndicator()),
            if (recovery != null) recovery,
          ]),
          error: (_, __) => Column(children: [
            Text(l.plusRetryError),
            TextButton(
                onPressed: () => ref.invalidate(plusCatalogProvider),
                child: Text(l.plusRetry)),
            if (recovery != null) recovery,
          ]),
          data: (catalog) => onSelectPurchase != null
              ? PlusCurrencyCheckout(
                  catalog: catalog,
                  busy: busy,
                  ready: ready,
                  renewal: renewal,
                  onRecover: onRecover,
                  onPurchase: onSelectPurchase!)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Text(l.plusPrice(catalog.amount)),
                      PlusPaymentTerms(
                          mint: catalog.mint, recipient: catalog.recipient),
                      FilledButton(
                          onPressed: busy ? null : onPurchase,
                          child: Text(l.plusCreatePayment)),
                    ]),
        );
  }
}

class PlusPendingPayment extends StatelessWidget {
  const PlusPendingPayment(
      {super.key,
      required this.order,
      required this.busy,
      required this.onRefresh});
  final PlusOrder order;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final awaiting = order.status == PlusPaymentStatus.awaitingPayment;
    final mainnet = order.network == 'solana-mainnet';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(mainnet
          ? l.plusPaidPrice(
              formatPlusAmount(order.amountAtomic,
                  decimals: order.tokenDecimals ?? 9),
              order.asset ?? '')
          : l.plusPrice(formatPlusAmount(order.amountAtomic))),
      Text(awaiting ? l.plusAwaiting : l.plusIssuing),
      PlusPaymentTerms(
          mint: order.mint, recipient: order.recipient, mainnet: mainnet),
      if (awaiting)
        Center(
            child: Semantics(
                label: l.plusCreatePayment,
                child: QrImageView(
                    data: order.paymentUri,
                    size: 220,
                    backgroundColor: Colors.white))),
      TextButton.icon(
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh),
          label: Text(l.plusRefresh)),
    ]);
  }
}
