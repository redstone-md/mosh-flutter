// Widget test for `PersistenceWarningBanner` (1-в-1 with React's
// `PersistenceWarningBanner` in
// src/features/private-dm/NewSessionPanel.parts.tsx). Asserts the localized
// title + body render and the banner exposes a `Semantics` container so
// screen readers announce it as a status region (React `role="status"`).
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
    // React appends ` Reason: <error>` (leading space) to the unavailable body.
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

  testWidgets(
      'exposes a Semantics container labeled with title + body (React role="status")',
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
    // The banner wraps itself in Semantics(container: true, label: ...)
    // so the screen reader announces "title. body" as a status region.
    // Read the merged semantics node for the banner widget directly.
    // The merged semantics node carries the title + body (Flutter joins the
    // child Text labels of the Column); assert both substrings are present so
    // the status region announces the full warning (React role="status").
    final label = tester
        .getSemantics(find.byType(PersistenceWarningBanner))
        .getSemanticsData()
        .label;
    expect(label, contains(title));
    expect(label, contains(body));
  });

  testWidgets('omits a semantic label on the alert icon (React aria-hidden)',
      (tester) async {
    final warning = PersistenceWarning(
      kind: PersistenceWarningKind.unavailable,
      reason: null,
    );
    await pumpScreen(
        tester, Scaffold(body: PersistenceWarningBanner(warning: warning)));

    // The warning_amber icon renders; its ExcludeSemantics wrapper is the one
    // that is an ancestor of the icon (the MaterialApp/Scaffold add their own
    // ExcludeSemantics nodes, so scope the finder to the icon's ancestors).
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.warning_amber_rounded),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });
}
