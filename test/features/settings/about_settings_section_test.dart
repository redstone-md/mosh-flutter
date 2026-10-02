import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/settings/app_package_info_provider.dart';
import 'package:mosh/src/features/settings/settings_content.dart';
import 'package:mosh/src/features/settings/settings_navigation.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';

import '../../support/pump.dart';
import '../../support/settings.dart';

PackageInfo _package({String version = '9.8.7-dev', String build = '42'}) =>
    PackageInfo(
      appName: 'Mosh',
      packageName: 'dev.mosh',
      version: version,
      buildNumber: build,
    );

Future<void> _pump(
  WidgetTester tester, {
  Future<PackageInfo> Function()? load,
  Size size = const Size(1200, 800),
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body:
                  SettingsContent(section: SettingsSection.about, wide: false),
            ),
          ),
        ),
      ),
    ),
    overrides: [
      if (load != null) appPackageInfoProvider.overrideWith((ref) => load()),
    ],
  );
}

void main() {
  testWidgets('a failed package read keeps About usable with unavailable text',
      (tester) async {
    await _pump(tester,
        load: () async => throw StateError('package unavailable'));
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('Mosh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the installed version includes platform build overrides',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Mosh',
      packageName: 'dev.mosh',
      version: '9.8.7-dev',
      buildNumber: '42',
      buildSignature: '',
    );
    await _pump(tester);
    expect(find.text('Version 9.8.7-dev · build 42'), findsOneWidget);
  });

  testWidgets('pending metadata keeps protection visible and completes safely',
      (tester) async {
    final pending = Completer<PackageInfo>();
    await _pump(tester, load: () => pending.future);
    expect(find.text('Reading version…'), findsOneWidget);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.cryptoNoticeBody), findsOneWidget);
    pending.complete(_package(build: ''));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7-dev'), findsOneWidget);
    expect(find.text('Reading version…'), findsNothing);
  });

  testWidgets('missing version is unavailable rather than an invented build',
      (tester) async {
    await _pump(tester, load: () async => _package(version: ''));
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.textContaining('build 42'), findsNothing);
  });

  testWidgets('late metadata after leaving the screen causes no UI update',
      (tester) async {
    final pending = Completer<PackageInfo>();
    await _pump(tester, load: () => pending.future);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_package());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('About restores details and scroll independently on return',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      appPackageInfoProvider.overrideWith((ref) async => _package()),
    ]);
    addTearDown(container.dispose);
    container
        .read(settingsSectionProvider.notifier)
        .select(SettingsSection.about);
    await pumpScreen(
        tester, Theme(data: buildMoshTheme(), child: const SettingsScreen()),
        container: container);
    final details = find.text('More about protection');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    final scroller = find.descendant(
        of: find.byType(SettingsContent), matching: find.byType(Scrollable));
    final position = tester.state<ScrollableState>(scroller).position;
    final offset = position.maxScrollExtent / 2;
    expect(offset, greaterThan(0));
    position.jumpTo(offset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.textContaining('public trackers'), findsOneWidget);
    expect(tester.state<ScrollableState>(scroller).position.pixels, offset);
    expect(find.text('Version 9.8.7-dev · build 42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('Russian About at $width and scale $scale wraps and scrolls',
        (tester) async {
      await _pump(tester,
          load: () async => _package(),
          size: Size(width, 844),
          scale: scale,
          locale: const Locale('ru'));
      final details = find.text('Подробнее о защите');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      final body = find.textContaining('публичные трекеры');
      await tester.ensureVisible(body);
      expect(body, findsOneWidget);
      expect(find.textContaining('Версия 9.8.7-dev'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('returning to About retries failed metadata in the same scope',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var reads = 0;
    final container = ProviderContainer(overrides: [
      ...settingsAudioOverrides(),
      appPackageInfoProvider.overrideWith((ref) async {
        reads++;
        if (reads == 1) throw StateError('package unavailable');
        return _package();
      }),
    ]);
    addTearDown(container.dispose);
    container
        .read(settingsSectionProvider.notifier)
        .select(SettingsSection.about);
    await pumpScreen(
        tester, Theme(data: buildMoshTheme(), child: const SettingsScreen()),
        container: container);
    expect(find.text('Version unavailable'), findsOneWidget);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7-dev · build 42'), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
}
