// 1-в-1 Flutter port of React's `PersistenceWarningBanner`
// (src/features/private-dm/NewSessionPanel.parts.tsx) and its CSS classes
// `.persistence-warning` / `.persistence-warning-icon` in
// src/features/private-dm/styles/desktop-shell.css.
import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

// CSS literal colors (theme.css): --warn #e8b65a, --fg-2 #a8aeb0, --fg-3 #6b7075.
const Color _kWarnColor = Color(0xFFE8B65A);
const Color _kFg3Color = Color(0xFF6B7075);
// CSS rgba(232, 182, 90, 0.08/0.12/0.28) -> alpha 0.08=21, 0.12=31, 0.28=71.
const Color _kBgColor = Color(0x15E8B65A);
const Color _kIconBgColor = Color(0x1FE8B65A);
const Color _kBorderColor = Color(0x47E8B65A);

class PersistenceWarningBanner extends StatelessWidget {
  const PersistenceWarningBanner({super.key, required this.warning});

  final PersistenceWarning warning;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isUnavailable = warning.kind == PersistenceWarningKind.unavailable;
    // React prefixes the persistence error with ` Reason: ` (leading space);
    // the gateway-error body already embeds `Reason: ` in the ARB string.
    final unavailableReason =
        warning.reason != null ? ' Reason: ${warning.reason}' : '';
    final title = isUnavailable
        ? l.persistenceWarningUnavailableTitle
        : l.persistenceWarningErrorTitle;
    final body = isUnavailable
        ? l.persistenceWarningUnavailableBody(unavailableReason)
        : l.persistenceWarningErrorBody(warning.reason ?? '');

    return Semantics(
      container: true,
      label: '$title. $body',
      child: Container(
        // CSS: padding 11px 12px; border 1px solid; border-radius 12px;
        // background rgba(232,182,90,0.08); color var(--fg-2).
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: _kBgColor,
          border: Border.all(color: _kBorderColor, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CSS .persistence-warning-icon: 26x26, radius 8, bg 0.12, warn.
            ExcludeSemantics(
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _kIconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                // Tabler IconAlertTriangle size=15 -> Material triangle alert.
                child: const Icon(Icons.warning_amber_rounded,
                    size: 15, color: _kWarnColor),
              ),
            ),
            const SizedBox(width: 10),
            // CSS .persistence-warning div: flex column, gap 3px, min-width 0.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CSS strong: warn color, 12.5px.
                  Text(
                    title,
                    style: const TextStyle(
                      color: _kWarnColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // CSS span: fg-3, 11.5px, line-height 1.5, overflow-wrap anywhere.
                  Text(
                    body,
                    softWrap: true,
                    style: const TextStyle(
                      color: _kFg3Color,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
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
