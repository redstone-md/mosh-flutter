import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/onboarding/first_run_profile.dart';
import 'package:mosh/src/features/onboarding/first_run_provider.dart';
import 'package:mosh/src/features/plus/plus_catalog.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';

import '../../support/first_run.dart';
import '../../support/plus/mainnet_fakes.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'profile scroll and delayed payment details restore independently',
      (tester) async {
    final catalog = Completer<PlusCatalog>();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await _pumpProfile(tester, catalog.future, visible);
    final scroll = find.byType(Scrollable).first;
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 500));
    final context = tester.element(scroll);
    expect(PageStorage.of(context).readState(context), isA<double>());

    catalog.complete(PlusCatalog.fromJson({
      ...mainnetCatalog,
      'purchases_enabled': false
    }, mainnetConfig.issuerKey, mainnet: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Purchases paused'), findsOneWidget);
    final details = find.text('Payment details & terms');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    final mint =
        find.text('Token mint: ${mainnetCatalog['assets'][0]['mint']}');
    expect(mint, findsOneWidget);

    await tester.drag(scroll, const Offset(0, -60));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scroll).position.pixels;
    expect(offset, greaterThan(0));
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.state<ScrollableState>(scroll).position.pixels,
        closeTo(offset, 0.01));
    expect(mint, findsOneWidget);
  });
}

Future<void> _pumpProfile(WidgetTester tester, Future<PlusCatalog> catalog,
    ValueNotifier<bool> visible) async {
  tester.view.physicalSize = const Size(1100, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    firstRunStoreProvider.overrideWithValue(MemoryFirstRunStore(
        const FirstRunProfile(displayName: 'Saved name', completed: true))),
    plusConfigProvider.overrideWithValue(mainnetConfig),
    plusCommandsProvider.overrideWithValue(MainnetTestCommands()),
    plusCatalogProvider.overrideWith((ref) => catalog),
    plusPollIntervalProvider.overrideWithValue(null),
  ]);
  addTearDown(container.dispose);
  await pumpScreen(
      tester,
      Scaffold(
          body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, shown, _) => shown
                  ? const SettingsContent(
                      section: SettingsSection.profile, wide: true)
                  : const SizedBox.shrink())),
      container: container,
      settle: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
