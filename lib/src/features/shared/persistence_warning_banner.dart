import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

class PersistenceWarningBanner extends StatelessWidget {
  const PersistenceWarningBanner({super.key, required this.warning});

  final PersistenceWarning warning;

  /// The localized title and body for [warning].
  (String, String) _copy(AppLocalizations l) {
    final reason = warning.reason;
    return switch (warning.kind) {
      // The persistence error is appended as ` <persistenceWarningReason>`
      // (leading space); the gateway-error body embeds its own `Reason:`.
      PersistenceWarningKind.unavailable => (
          l.persistenceWarningUnavailableTitle,
          l.persistenceWarningUnavailableBody(
              reason == null ? '' : ' ${l.persistenceWarningReason(reason)}'),
        ),
      PersistenceWarningKind.error => (
          l.persistenceWarningErrorTitle,
          l.persistenceWarningErrorBody(reason ?? ''),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = _copy(AppLocalizations.of(context)!);
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: MoshColors.warnSurface,
          border: Border.all(color: MoshColors.warnBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IconPlate(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(color: MoshColors.warn),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: text.bodySmall?.copyWith(color: MoshColors.fg3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The banner's 26px warn-tinted plate around the alert glyph.
class _IconPlate extends StatelessWidget {
  const _IconPlate();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MoshColors.warnIconSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.warning_amber, size: 15, color: MoshColors.warn),
    );
  }
}
