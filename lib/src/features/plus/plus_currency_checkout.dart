import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'plus_catalog.dart';
import 'plus_payment_details.dart';

class PlusCurrencyCheckout extends StatefulWidget {
  const PlusCurrencyCheckout(
      {super.key,
      required this.catalog,
      required this.busy,
      required this.ready,
      required this.renewal,
      this.onRecover,
      required this.onPurchase});
  final PlusCatalog catalog;
  final bool busy;
  final bool ready;
  final bool renewal;
  final ValueChanged<String> onPurchase;
  final VoidCallback? onRecover;
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
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(l.plusPaidPrice(asset.amount, asset.id),
                style: Theme.of(context).textTheme.headlineSmall),
            _currencies(),
          ]),
      const SizedBox(height: 4),
      Text(l.plusOneTimeHint, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      _actions(l, asset),
      const SizedBox(height: 4),
      PlusPaymentDetails(catalog: widget.catalog, asset: asset),
    ]);
  }

  Widget _currencies() => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in widget.catalog.assets)
          ChoiceChip(
              label: Text(item.id),
              selected: item.id == _asset,
              onSelected:
                  widget.busy ? null : (_) => setState(() => _asset = item.id))
      ]);

  Widget _actions(AppLocalizations l, PlusAsset asset) => Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
                onPressed: widget.busy ||
                        !widget.ready ||
                        !widget.catalog.purchasesEnabled
                    ? null
                    : () => widget.onPurchase(asset.id),
                child: Text(!widget.catalog.purchasesEnabled
                    ? l.plusSalesPaused
                    : widget.renewal
                        ? l.plusRenew
                        : l.plusBuy)),
            if (widget.onRecover != null)
              TextButton(
                  onPressed:
                      widget.busy || !widget.ready ? null : widget.onRecover,
                  child: Text(l.plusRecover)),
          ]);
}
