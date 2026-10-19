import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'plus_catalog.dart';
import 'plus_checkout.dart';

class PlusCurrencyCheckout extends StatefulWidget {
  const PlusCurrencyCheckout(
      {super.key,
      required this.catalog,
      required this.busy,
      required this.ready,
      required this.renewal,
      required this.onPurchase});
  final PlusCatalog catalog;
  final bool busy;
  final bool ready;
  final bool renewal;
  final ValueChanged<String> onPurchase;
  @override
  State<PlusCurrencyCheckout> createState() => _PlusCurrencyCheckoutState();
}

class _PlusCurrencyCheckoutState extends State<PlusCurrencyCheckout> {
  String _asset = 'USDC';
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final asset = widget.catalog.assets.firstWhere((a) => a.id == _asset);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in widget.catalog.assets)
          ChoiceChip(
              label: Text(item.id),
              selected: item.id == _asset,
              onSelected:
                  widget.busy ? null : (_) => setState(() => _asset = item.id))
      ]),
      const SizedBox(height: 8),
      Text(l.plusPaidPrice(asset.amount, asset.id)),
      PlusPaymentTerms(
          mint: asset.mint, recipient: widget.catalog.recipient, mainnet: true),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (widget.catalog.termsUrl case final url?)
          TextButton(
              onPressed: () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
              child: Text(l.plusPurchaseTerms)),
        if (widget.catalog.supportUrl case final url?)
          TextButton(
              onPressed: () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
              child: Text(l.plusPaymentSupport)),
      ]),
      if (!widget.catalog.purchasesEnabled) Text(l.plusUnavailable),
      FilledButton(
          onPressed:
              widget.busy || !widget.ready || !widget.catalog.purchasesEnabled
                  ? null
                  : () => widget.onPurchase(asset.id),
          child: Text(widget.renewal ? l.plusRenew : l.plusCreatePayment)),
    ]);
  }
}
