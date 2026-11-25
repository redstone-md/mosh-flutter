// Contracts of the Banner card's notice: what it ends with, how it reads on
// a toned plate in both palettes, and what a screen reader hears.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart';

import '../../support/contrast.dart';

Future<void> _pump(WidgetTester tester, Widget notice,
        [MoshColors colors = MoshColors.dark]) =>
    tester.pumpWidget(MaterialApp(
      theme: buildMoshTheme(colors),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: notice),
    ));

void main() {
  testWidgets('a chat error that can be put right ends with Retry alone',
      (tester) async {
    var retries = 0, closes = 0;
    await _pump(
        tester,
        ChatErrorBanner(
            message: 'Not delivered',
            onRetry: () => retries++,
            onClose: () => closes++));

    expect(find.byTooltip('Close'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect((retries, closes), (1, 0));
  });

  testWidgets('a chat error with nothing to do about it can be closed',
      (tester) async {
    var closes = 0;
    await _pump(tester,
        ChatErrorBanner(message: 'Already in a call', onClose: () => closes++));

    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    expect(closes, 1);
  });

  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    testWidgets('the controls of a toned plate read on it ($palette)',
        (tester) async {
      await _pump(
          tester,
          Column(children: [
            MoshNotice(
                tone: MoshNoticeTone.error,
                icon: MoshIcons.error,
                title: 'Not delivered',
                actionLabel: 'Retry',
                onAction: () {}),
            MoshNotice(
                tone: MoshNoticeTone.warning,
                icon: MoshIcons.warning,
                title: 'History is not being saved',
                onClose: () {}),
          ]),
          colors);

      final retry = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(
          contrastRatio(retry.style!.foregroundColor!.resolve({})!,
              colors.errorContainer),
          greaterThanOrEqualTo(4.5));
      final close = tester.widget<IconButton>(find.byType(IconButton));
      expect(contrastRatio(close.color!, colors.warningContainer),
          greaterThanOrEqualTo(3));
    });
  }

  testWidgets('a notice is read as one sentence, and only an error interrupts',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
        tester,
        const Column(children: [
          MoshNotice(
              tone: MoshNoticeTone.secure,
              icon: MoshIcons.lock,
              title: 'End-to-end encrypted group',
              detail: 'New members cannot see earlier messages.'),
          MoshNotice(
              tone: MoshNoticeTone.error,
              icon: MoshIcons.error,
              title: 'Group out of sync',
              detail: 'Ask an administrator to invite you again'),
        ]));

    expect(
        find.bySemanticsLabel('End-to-end encrypted group. '
            'New members cannot see earlier messages.'),
        findsOneWidget);
    bool interrupts(int i) => tester
        .getSemantics(find.byType(MoshNotice).at(i))
        .flagsCollection
        .isLiveRegion;
    expect(interrupts(0), isFalse);
    expect(interrupts(1), isTrue);
    semantics.dispose();
  });
}
