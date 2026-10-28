import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'plus_provider.dart';
import 'plus_catalog.dart';
import 'plus_currency_checkout.dart';
import 'plus_payment_details.dart';

export 'plus_payment_details.dart' show PlusPaymentTerms;

/// Hands a `solana:` payment request to a wallet app on this device.
/// Injectable, so a widget test records the attempt instead of a plugin call.
typedef PlusWalletOpener = Future<bool> Function(Uri payment);

final plusWalletOpenerProvider = Provider<PlusWalletOpener>(
  (_) => (payment) => launchUrl(payment, mode: LaunchMode.externalApplication),
);

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

class PlusPendingPayment extends ConsumerWidget {
  const PlusPendingPayment(
      {super.key,
      required this.order,
      required this.busy,
      required this.onRefresh});
  final PlusOrder order;
  final bool busy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      if (awaiting) _PaymentLinkActions(paymentUri: order.paymentUri),
      TextButton.icon(
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh),
          label: Text(l.plusRefresh)),
    ]);
  }
}

/// Copy and, on a phone, open the payment request: scanning a QR shown on the
/// same phone that holds the wallet is not possible.
class _PaymentLinkActions extends ConsumerWidget {
  const _PaymentLinkActions({required this.paymentUri});
  final String paymentUri;

  static bool get _hasWalletApps =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_hasWalletApps)
            FilledButton.icon(
                onPressed: () => _open(ref, l),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(l.plusOpenWallet)),
          OutlinedButton.icon(
              onPressed: () => _copy(ref, l),
              icon: const Icon(Icons.copy_outlined),
              label: Text(l.plusCopyPayment)),
        ]);
  }

  // Read from ref before awaiting: the card can close while the platform call
  // is pending, and a ref is unusable once its widget is unmounted.
  Future<void> _open(WidgetRef ref, AppLocalizations l) async {
    final toaster = ref.read(toasterProvider);
    final openWallet = ref.read(plusWalletOpenerProvider);
    bool opened;
    try {
      opened = await openWallet(Uri.parse(paymentUri));
    } on PlatformException {
      opened = false;
    }
    if (!opened) toaster.show(l.plusWalletNotFound, kind: ToastKind.error);
  }

  Future<void> _copy(WidgetRef ref, AppLocalizations l) async {
    final toaster = ref.read(toasterProvider);
    await Clipboard.setData(ClipboardData(text: paymentUri));
    toaster.show(l.messageCopied);
  }
}
