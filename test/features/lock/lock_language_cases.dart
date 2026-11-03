import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/lock/mosh_lock_app.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import 'package:mosh/src/state/locale_preference_store.dart';

import '../../support/locale.dart';

void main() {
  testWidgets('the startup lock screen uses the saved interface language',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localePreferenceStoreProvider
            .overrideWithValue(MemoryLocalePreferenceStore(const Locale('ru'))),
      ],
      child: MoshLockApp(
          screen: MoshLockScreen(
        retry: () async {},
        swapTo: (_) {},
        nextApp: const SizedBox(),
      )),
    ));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context).languageCode, 'ru');
    expect(find.text(AppLocalizations.of(context)!.lockScreenTitle),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
