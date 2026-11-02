// Widget test for `PersistenceWarningBanner`. Asserts the localized
// title + body render and a screen reader hears them once, as one region.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/persistence_warning_banner.dart';
import 'package:mosh/src/state/persistence_warning_provider.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('renders localized title + body for the unavailable branch',
      (tester) async {
    final warning = PersistenceWarning(
      kind: PersistenceWarningKind.unavailable,
      reason: 'no instance',
    );
    await pumpScreen(
        tester, Scaffold(body: PersistenceWarningBanner(warning: warning)));

    final l = AppLocalizations.of(
        tester.element(find.byType(PersistenceWarningBanner)))!;
    expect(find.text(l.persistenceWarningUnavailableTitle), findsOneWidget);
    // The unavailable body gets ` Reason: <error>` (leading space) appended.
    expect(
      find.text(l.persistenceWarningUnavailableBody(' Reason: no instance')),
      findsOneWidget,
    );
  });

  testWidgets('renders localized title + body for the error branch',
      (tester) async {
    final warning = PersistenceWarning(
      kind: PersistenceWarningKind.error,
      reason: 'gateway exploded',
    );
    await pumpScreen(
        tester, Scaffold(body: PersistenceWarningBanner(warning: warning)));

    final l = AppLocalizations.of(
        tester.element(find.byType(PersistenceWarningBanner)))!;
    expect(find.text(l.persistenceWarningErrorTitle), findsOneWidget);
    expect(
      find.text(l.persistenceWarningErrorBody('gateway exploded')),
      findsOneWidget,
    );
  });

  testWidgets('announces title and body once, without the icon',
      (tester) async {
    final warning = PersistenceWarning(
      kind: PersistenceWarningKind.unavailable,
      reason: 'no instance',
    );
    await pumpScreen(
        tester, Scaffold(body: PersistenceWarningBanner(warning: warning)));

    final l = AppLocalizations.of(
        tester.element(find.byType(PersistenceWarningBanner)))!;
    final title = l.persistenceWarningUnavailableTitle;
    final body = l.persistenceWarningUnavailableBody(' Reason: no instance');
    expect(
      tester.getSemantics(find.byType(PersistenceWarningBanner)),
      isSemantics(label: '$title. $body'),
    );
  });
}
