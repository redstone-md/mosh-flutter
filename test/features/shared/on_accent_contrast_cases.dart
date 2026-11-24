// Text on the theme's danger fills must read at WCAG AA.
//
// Audit (2026-09-21) MEDIUM: near-white text on the light danger fill came to
// ~3.1:1, a fail for the small text the confirm button and the error banner
// render. The theme's own pairs are pinned in test/app/mosh_theme_cases.dart;
// these tests pin that the danger surfaces paint a readable pair.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, buildMoshTheme, moshThemeData;
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';

import '../../support/contrast.dart';

Widget _host(Widget child) => MaterialApp(
      theme: moshThemeData,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('the error banner body reads the on-container token',
      (tester) async {
    await tester.pumpWidget(_host(const ChatErrorBanner(message: 'boom')));

    final text = tester.widget<Text>(find.text('boom'));
    expect(text.style!.color, moshThemeData.colorScheme.onErrorContainer);
  });

  for (final (name, theme) in [
    ('dark', moshThemeData),
    ('light', buildMoshTheme(MoshColors.light)),
  ]) {
    testWidgets(
        'the confirm danger button label reads at 4.5:1 on its fill ($name)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: ConfirmDialog(
                title: 'Leave chat?',
                body: 'This will erase the keys. Are you sure?',
                confirmLabel: 'Leave',
                cancelLabel: 'Cancel',
                onCancel: () {},
                onConfirm: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Leave'),
          matching: find.byType(FilledButton),
        ),
      );
      final label = button.style!.foregroundColor!.resolve({})!;
      final fill = button.style!.backgroundColor!.resolve({})!;
      expect(contrastRatio(label, fill), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a dark custom dangerColor flips to the light foreground',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: moshThemeData,
        home: Scaffold(
          body: Center(
            child: ConfirmDialog(
              title: 'Leave chat?',
              body: 'This will erase the keys. Are you sure?',
              confirmLabel: 'Leave',
              cancelLabel: 'Cancel',
              // A themable dark fill: the dark on-danger ink would vanish.
              dangerColor: const Color(0xFF7A1E12),
              onCancel: () {},
              onConfirm: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Leave'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
        button.style?.foregroundColor?.resolve({}), MoshColors.dark.onSurface);
  });
}
