import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/shared/mosh_disclosure.dart';
import 'package:url_launcher/url_launcher.dart';
import 'plus_catalog.dart';

/// Full payment and privacy information stays available before checkout.
class PlusPaymentDetails extends StatelessWidget {
  const PlusPaymentDetails(
      {super.key, required this.catalog, required this.asset});
  final PlusCatalog catalog;
  final PlusAsset asset;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme.bodySmall!;
    // Expansion and selectable text scrolling need independent storage slots.
    return MoshDisclosure(
      key: const PageStorageKey('plus-payment-details'),
      label: l.plusPaymentDetails,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s3),
        child: DefaultTextStyle(
          style: text,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PlusPaymentTerms(
                mint: asset.mint, recipient: catalog.recipient, mainnet: true),
            Text(l.plusMainnetPrivacy),
            const SizedBox(height: MoshSpace.s2),
            Wrap(spacing: MoshSpace.s2, runSpacing: MoshSpace.s1, children: [
              if (catalog.termsUrl case final url?)
                TextButton(
                    onPressed: () =>
                        launchUrl(url, mode: LaunchMode.externalApplication),
                    child: Text(l.plusPurchaseTerms)),
              if (catalog.supportUrl case final url?)
                TextButton(
                    onPressed: () =>
                        launchUrl(url, mode: LaunchMode.externalApplication),
                    child: Text(l.plusPaymentSupport)),
            ]),
          ]),
        ),
      ),
    );
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectableText('${l.plusMint}: $mint',
            key: PageStorageKey('plus-mint:$mint')),
        SelectableText('${l.plusRecipient}: $recipient',
            key: PageStorageKey('plus-recipient:$recipient')),
        const SizedBox(height: 8),
        Text(mainnet ? l.plusSupportTerm : l.plusTerm),
        const SizedBox(height: 8),
        Text(mainnet ? l.plusMainnetNotice : l.plusNetworkNotice),
      ]),
    );
  }
}
