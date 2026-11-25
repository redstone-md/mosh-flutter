import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';

/// The Storage kind of the Banner card: history is not being saved, and why.
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
    return MoshNotice(
      tone: MoshNoticeTone.warning,
      icon: MoshIcons.warning,
      title: title,
      detail: body,
    );
  }
}
