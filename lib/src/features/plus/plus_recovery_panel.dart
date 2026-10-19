import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/plus/recovery_types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PlusRecoveryPanel extends StatelessWidget {
  const PlusRecoveryPanel({super.key, required this.session});
  final PlusRecoverySession session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (session.expiresAtMs.toInt() <= DateTime.now().millisecondsSinceEpoch) {
      return Text(l.plusRecoveryExpired);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Text(l.plusRestoreTerms),
      const SizedBox(height: 8),
      Text(l.plusDeviceCode),
      SelectableText(session.code,
          style: Theme.of(context).textTheme.headlineSmall),
      if (session.url case final url?) ...[
        Text(l.plusRecoveryWaiting),
        Center(
            child: QrImageView(
                data: url,
                size: 220,
                backgroundColor: Colors.white,
                semanticsLabel: l.plusRecover)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: url)),
              icon: const Icon(Icons.copy_outlined),
              label: Text(l.plusCopyRecovery)),
          OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new),
              label: Text(l.plusOpenRecovery)),
        ]),
      ],
      if (session.completedOrders > 0)
        Text(l.plusRecoveryFinished(session.completedOrders.toString())),
    ]);
  }
}
