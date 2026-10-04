import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/state/locale_provider.dart';

import '../../support/first_run.dart';
import '../../support/locale.dart';

AppLocalizations _labels(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MoshSelect<Locale?>)))!;

Future<FirstRunHarness> _pump(
  WidgetTester tester,
  MemoryLocalePreferenceStore store, {
  Size size = const Size(1200, 850),
}) async {
  final harness = FirstRunHarness(
      profile: const FirstRunProfile(displayName: 'Name', completed: true),
      localeStore: store);
  await harness.pump(tester, size: size);
  harness.container
      .read(settingsSectionProvider.notifier)
      .select(SettingsSection.profile);
  appRouter.go(AppRoutes.settings);
  await tester.pumpAndSettle();
  if (size.width < 800) {
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  }
  return harness;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byType(MoshSelect<Locale?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'System follows OS changes and unsupported languages fall back to English',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final harness = await _pump(tester, MemoryLocalePreferenceStore());
    expect(_labels(tester).localeName, 'en');
    tester.platformDispatcher.localesTestValue = [const Locale('ru', 'RU')];
    await tester.pumpAndSettle();
    expect(_labels(tester).localeName, 'ru');
    expect(harness.container.read(localeProvider), isNull);
    tester.platformDispatcher.localesTestValue = [const Locale('ja')];
    await tester.pumpAndSettle();
    expect(_labels(tester).localeName, 'en');
  });

  testWidgets(
      'first frame resolves the supported OS language without an override',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('ru', 'RU')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final harness = FirstRunHarness(profile: const FirstRunProfile());
    await harness.pump(tester);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(harness.container.read(localeProvider), isNull);
  });

  testWidgets(
      'manual selection applies immediately, persists, and can return to System',
      (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final store = MemoryLocalePreferenceStore();
    final harness = await _pump(tester, store);
    await _choose(tester, 'Русский');
    expect(_labels(tester).localeName, 'ru');
    expect(store.locale, const Locale('ru'));
    tester.platformDispatcher.localesTestValue = [const Locale('en', 'GB')];
    await tester.pumpAndSettle();
    expect(_labels(tester).localeName, 'ru');
    await _choose(tester, _labels(tester).interfaceLanguageSystem);
    expect(_labels(tester).localeName, 'en');
    expect(store.locale, isNull);
    expect(harness.container.read(localeProvider), isNull);
  });

  testWidgets(
      'a pending save disables selection; refusal retains the saved language',
      (tester) async {
    final pending = Completer<void>();
    final store = MemoryLocalePreferenceStore(const Locale('en'))
      ..pendingWrite = pending.future
      ..writeError = Exception('disk refused');
    final harness = await _pump(tester, store);
    await tester.tap(find.byType(MoshSelect<Locale?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MoshSelect<Locale?>>(find.byType(MoshSelect<Locale?>))
            .onChanged,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(harness.container.read(localeProvider), const Locale('en'));
    expect(
        find.text(_labels(tester).interfaceLanguageSaveError), findsOneWidget);
    store.writeError = null;
    await _choose(tester, 'Русский');
    expect(_labels(tester).localeName, 'ru');
    expect(find.textContaining('Could not save'), findsNothing);
  });

  testWidgets('narrow settings use the existing language choice sheet',
      (tester) async {
    final store = MemoryLocalePreferenceStore(const Locale('en'));
    await _pump(tester, store, size: const Size(390, 844));
    await _choose(tester, 'Русский');
    expect(_labels(tester).localeName, 'ru');
    expect(store.locale, const Locale('ru'));
    expect(tester.takeException(), isNull);
  });
}
