import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'plus_provider.dart';
import 'plus_catalog.dart';
import 'plus_currency_checkout.dart';

class PlusNewPayment extends ConsumerWidget {
  const PlusNewPayment(
      {super.key,
      required this.busy,
      required this.onPurchase,
      this.onSelectPurchase,
      this.ready = true,
      this.renewal = false});
  final bool busy;
  final VoidCallback onPurchase;
  final ValueChanged<String>? onSelectPurchase;
  final bool ready;
  final bool renewal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ref.watch(plusCatalogProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Column(children: [
            Text(l.plusRetryError),
            TextButton(
                onPressed: () => ref.invalidate(plusCatalogProvider),
                child: Text(l.plusRetry))
          ]),
          data: (catalog) => onSelectPurchase != null
              ? PlusCurrencyCheckout(
                  catalog: catalog,
                  busy: busy,
                  ready: ready,
                  renewal: renewal,
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

class PlusPaymentTerms extends StatelessWidget {
  const PlusPaymentTerms(
      {super.key,
      required this.mint,
      required this.recipient,
      this.mainnet = false});
  final String mint;
  final String recipient;
  final bool mainnet;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SelectableText('${l.plusMint}: $mint'),
          SelectableText('${l.plusRecipient}: $recipient'),
          const SizedBox(height: 8),
          Text(mainnet ? l.plusSupportTerm : l.plusTerm),
          const SizedBox(height: 8),
          Text(mainnet ? l.plusMainnetNotice : l.plusNetworkNotice),
        ]));
  }
}
