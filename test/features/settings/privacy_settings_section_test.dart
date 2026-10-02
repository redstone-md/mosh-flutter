import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';

import '../../support/privacy.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';

final _l = lookupAppLocalizations(const Locale('en'));

Finder _switch(String title) => find.widgetWithText(SwitchListTile, title);

Future<void> _tap(WidgetTester tester, String title) async {
  final target = find.text(title).first;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  PrivacyFixture fixture, {
  Size size = const Size(1000, 900),
  double textScale = 1,
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(fixture.dispose);
  await pumpScreen(
    tester,
    Theme(
      data: buildMoshTheme(),
      child: Builder(
          builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQueryData(
                      size: size, textScaler: TextScaler.linear(textScale)),
                  child: const Scaffold(
                    backgroundColor: MoshColors.bg0,
                    body: SettingsContent(
                        section: SettingsSection.privacy, wide: false),
                  ),
                ),
              )),
    ),
    overrides: fixture.overrides,
    settle: settle,
  );
}

void main() {
  testWidgets('details never hide the memory warning or change consent',
      (tester) async {
    final fixture = PrivacyFixture();
    await _pump(tester, fixture);
    expect(find.text(_l.settingsCrashReportsNativeWarning), findsOneWidget);
    expect(find.text(_l.settingsCrashReportsDetails), findsNothing);
    expect(find.text(_l.settingsReadReceiptsDetails), findsNothing);
    await _tap(tester, _l.settingsCrashReportsDetailsTitle);
    expect(find.text(_l.settingsCrashReportsDetails), findsOneWidget);
    await _tap(tester, _l.settingsCrashReportsDetailsTitle);
    await _tap(tester, _l.settingsReadReceiptsDetailsTitle);
    expect(find.text(_l.settingsCrashReportsNativeWarning), findsOneWidget);
    expect(find.text(_l.settingsCrashReportsDetails), findsNothing);
    expect(find.text(_l.settingsReadReceiptsDetails), findsOneWidget);
    expect(fixture.bridge.countOf(BridgeMethod.enableCrashReporting), 0);
    expect(fixture.bridge.countOf(BridgeMethod.setReadReceiptsEnabled), 0);
    expect(fixture.bridge.countOf(BridgeMethod.crashReportingSalt), 1);
    expect(fixture.bridge.countOf(BridgeMethod.readReceiptsEnabled), 1);
    expect(fixture.sdkEvents, isEmpty);
  });

  testWidgets('unavailable reporting does not disable read receipts',
      (tester) async {
    final fixture = PrivacyFixture(available: false);
    fixture.bridge.seedCrashReportingSalt('saved-consent');
    await _pump(tester, fixture);
    final crash =
        tester.widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle));
    expect(crash.onChanged, isNull);
    expect(find.text(_l.settingsCrashReportsUnavailable), findsOneWidget);
    await _tap(tester, _l.settingsReadReceiptsTitle);
    expect(await fixture.bridge.readReceiptsEnabled(), isTrue);
    expect(await fixture.bridge.crashReportingSalt(), 'saved-consent');
    expect(fixture.sdkEvents, isEmpty);
    expect(fixture.bridge.countOf(BridgeMethod.enableCrashReporting), 0);
  });

  testWidgets('pending consent reads keep both switches non-actionable',
      (tester) async {
    final fixture = PrivacyFixture();
    fixture.bridge
      ..hold(BridgeMethod.crashReportingSalt)
      ..hold(BridgeMethod.readReceiptsEnabled);
    await _pump(tester, fixture, settle: false);
    for (final title in [
      _l.settingsCrashReportsTitle,
      _l.settingsReadReceiptsTitle
    ]) {
      expect(tester.widget<SwitchListTile>(_switch(title)).onChanged, isNull);
      await tester.tap(_switch(title));
    }
    expect(fixture.bridge.countOf(BridgeMethod.enableCrashReporting), 0);
    expect(fixture.bridge.countOf(BridgeMethod.setReadReceiptsEnabled), 0);
    fixture.bridge
      ..release(BridgeMethod.crashReportingSalt)
      ..release(BridgeMethod.readReceiptsEnabled);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .onChanged,
        isNotNull);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsReadReceiptsTitle))
            .onChanged,
        isNotNull);
  });

  testWidgets('failed SDK startup rolls the card back and clears consent',
      (tester) async {
    final fixture = PrivacyFixture()..failStart = true;
    await _pump(tester, fixture);
    await _tap(tester, _l.settingsCrashReportsTitle);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .value,
        isFalse);
    expect(await fixture.bridge.crashReportingSalt(), isNull);
    expect(find.textContaining('SDK unavailable'), findsOneWidget);
    expect(find.text(_l.settingsCrashReportsNativeWarning), findsOneWidget);
    expect(fixture.sdkEvents, ['start', 'stop']);
    await _tap(tester, _l.settingsCrashReportsDetailsTitle);
    expect(find.textContaining('SDK unavailable'), findsOneWidget);
    expect(fixture.bridge.countOf(BridgeMethod.setReadReceiptsEnabled), 0);
  });

  testWidgets('failed reads remain disabled with visible errors and warning',
      (tester) async {
    final fixture = PrivacyFixture();
    fixture.bridge
      ..failNext(BridgeMethod.crashReportingSalt,
          error: StateError('consent unavailable'))
      ..failNext(BridgeMethod.readReceiptsEnabled,
          error: StateError('receipts unavailable'));
    await _pump(tester, fixture);
    expect(find.textContaining('consent unavailable'), findsOneWidget);
    expect(find.textContaining('receipts unavailable'), findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .onChanged,
        isNull);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsReadReceiptsTitle))
            .onChanged,
        isNull);
    expect(find.text(_l.settingsCrashReportsNativeWarning), findsOneWidget);
    await _tap(tester, _l.settingsCrashReportsDetailsTitle);
    expect(fixture.bridge.countOf(BridgeMethod.enableCrashReporting), 0);
    expect(fixture.bridge.countOf(BridgeMethod.setReadReceiptsEnabled), 0);
  });

  testWidgets('resizing during a write preserves its value and pending guard',
      (tester) async {
    final fixture = PrivacyFixture();
    fixture.bridge.hold(BridgeMethod.enableCrashReporting);
    await _pump(tester, fixture);
    await _tap(tester, _l.settingsCrashReportsTitle);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    final crash =
        tester.widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle));
    expect(crash.value, isTrue);
    expect(crash.onChanged, isNull);
    expect(fixture.bridge.countOf(BridgeMethod.crashReportingSalt), 1);
    expect(fixture.bridge.countOf(BridgeMethod.enableCrashReporting), 1);
    fixture.bridge.release(BridgeMethod.enableCrashReporting);
    await tester.pumpAndSettle();
    expect(fixture.sdkEvents, ['start']);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .onChanged,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the two cards write independently and preserve receipt rollback',
      (tester) async {
    final fixture = PrivacyFixture();
    await _pump(tester, fixture);
    await _tap(tester, _l.settingsCrashReportsTitle);
    expect(await fixture.bridge.crashReportingSalt(), isNotNull);
    expect(fixture.sdkEvents, ['start']);
    fixture.bridge.failNext(BridgeMethod.setReadReceiptsEnabled,
        error: StateError('storage unavailable'));
    await _tap(tester, _l.settingsReadReceiptsTitle);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsReadReceiptsTitle))
            .value,
        isFalse);
    expect(await fixture.bridge.readReceiptsEnabled(), isFalse);
    expect(find.textContaining('storage unavailable'), findsOneWidget);
    expect(fixture.sdkEvents, ['start']);
    await _tap(tester, _l.settingsReadReceiptsTitle);
    expect(await fixture.bridge.readReceiptsEnabled(), isTrue);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .onChanged,
        isNotNull);
    await _tap(tester, _l.settingsCrashReportsTitle);
    // Stream cancellation completes on the real event loop, beyond UI frames.
    await tester.runAsync(() async => await pumpEventQueue());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsCrashReportsTitle))
            .value,
        isFalse);
    expect(fixture.bridge.countOf(BridgeMethod.disableCrashReporting), 1);
    expect(await fixture.bridge.crashReportingSalt(), isNull);
    expect(fixture.sdkEvents, ['start', 'stop']);
    expect(await fixture.bridge.readReceiptsEnabled(), isTrue);
  });

  testWidgets('section return restores independent disclosures and scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = PrivacyFixture();
    addTearDown(fixture.dispose);
    final container = ProviderContainer(overrides: fixture.overrides);
    addTearDown(container.dispose);
    container
        .read(settingsSectionProvider.notifier)
        .select(SettingsSection.privacy);
    await pumpScreen(
        tester, Theme(data: buildMoshTheme(), child: const SettingsScreen()),
        container: container);
    await _tap(tester, _l.settingsCrashReportsDetailsTitle);
    await _tap(tester, _l.settingsReadReceiptsDetailsTitle);
    await _tap(tester, _l.settingsReadReceiptsTitle);
    final scroller = find.descendant(
        of: find.byType(SettingsContent), matching: find.byType(Scrollable));
    tester.state<ScrollableState>(scroller).position.jumpTo(40);
    await tester.pumpAndSettle();
    await _tap(tester, 'About');
    await _tap(tester, 'Privacy');
    expect(find.text(_l.settingsCrashReportsDetails), findsOneWidget);
    expect(find.text(_l.settingsReadReceiptsDetails), findsOneWidget);
    expect(tester.state<ScrollableState>(scroller).position.pixels, 40);
    expect(
        tester
            .widget<SwitchListTile>(_switch(_l.settingsReadReceiptsTitle))
            .value,
        isTrue);
    expect(fixture.bridge.countOf(BridgeMethod.setReadReceiptsEnabled), 1);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('Russian Privacy at $width with text scale $scale is usable',
        (tester) async {
      final fixture = PrivacyFixture();
      final ru = lookupAppLocalizations(const Locale('ru'));
      await _pump(tester, fixture,
          size: Size(width, 844), locale: const Locale('ru'), textScale: scale);
      await _tap(tester, ru.settingsCrashReportsDetailsTitle);
      await _tap(tester, ru.settingsReadReceiptsDetailsTitle);
      await _tap(tester, ru.settingsReadReceiptsTitle);
      expect(await fixture.bridge.readReceiptsEnabled(), isTrue);
      expect(find.text(ru.settingsCrashReportsNativeWarning), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
