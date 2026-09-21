// Text on the theme's light danger fills must be dark ink.
//
// Audit (2026-09-21) MEDIUM: `onError`/`onErrorContainer` mapped to fg1
// (near-white) on the light danger fill (#E86A5A) -- ~3.1:1, a WCAG AA fail
// for the small text the confirm button and the error banner render. The
// theme already solves the same problem for warn/info (`onTertiary` ->
// mossInk); these tests pin the same ink on danger and pin that the danger
// surfaces actually read the tokens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors, moshThemeData;
import 'package:mosh/src/features/shared/chat_error_banner.dart';
import 'package:mosh/src/features/shared/confirm_dialog.dart';

Widget _host(Widget child) => MaterialApp(
      theme: moshThemeData,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('theme on-danger tokens are dark ink, not near-white fg1',
      (tester) async {
    expect(moshThemeData.colorScheme.onError, MoshColors.mossInk);
    expect(moshThemeData.colorScheme.onErrorContainer, MoshColors.mossInk);
  });

  testWidgets('the error banner body reads the on-container token',
      (tester) async {
    await tester.pumpWidget(_host(const ChatErrorBanner(message: 'boom')));

    final text = tester.widget<Text>(find.text('boom'));
    expect(text.style!.color, moshThemeData.colorScheme.onErrorContainer);
  });

  testWidgets('the confirm danger button label reads the on-error token',
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
      button.style?.foregroundColor?.resolve({}),
      moshThemeData.colorScheme.onError,
    );
  });
}
