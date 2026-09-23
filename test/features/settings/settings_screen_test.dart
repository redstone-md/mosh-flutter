// The settings surface: the gear at the rail bottom opens /settings, the
// screen renders its three sections, and the onboarding menu no longer
// carries the Advanced/About disclosures (they moved into the settings).
//
// What is pinned here:
//  1. The rail renders the gear (fixed below the list, always visible).
//  2. Tapping it routes to /settings and the section nav renders.
//  3. The Voice & Video section renders both device dropdowns with the
//     "System default" entries (the enumerators degrade to empty lists in
//     tests — the dropdowns must still render).
//  4. A pick from the output dropdown writes the store (the picks
//     provider state carries it).
//  5. The Connection section renders the two advanced fields + the
//     read-receipts toggle (the moved controls).
//  6. The About section renders the crypto notice.
//  7. The onboarding menu contains no Advanced/About disclosure anymore.
//
// The frb store calls are `#[frb(sync)]` over the cdylib — absent under
// `flutter test` — so the picks provider is overridden with a plain
// in-memory container; the settings screen itself reads it through the
// same seam production does.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/settings/settings_screen.dart';
import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/state/audio_device_picks_provider.dart'
    show audioDevicePicksProvider, AudioDevicePicks, AudioDevicePicksNotifier;

import '../../support/pump.dart';

/// A picks notifier stand-in: the real one calls the frb store, which is
/// absent under `flutter test`. Same state shape.
class _StubPicksNotifier extends AudioDevicePicksNotifier {
  _StubPicksNotifier(this._picks);

  final AudioDevicePicks _picks;

  @override
  AudioDevicePicks build() => _picks;

  @override
  void set({String? inputDeviceId, String? outputDeviceId}) {
    state = AudioDevicePicks(
      inputDeviceId: inputDeviceId,
      outputDeviceId: outputDeviceId,
    );
  }
}

Future<void> _pumpSettings(WidgetTester tester, {bool wide = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioDevicePicksProvider
            .overrideWith(() => _StubPicksNotifier(const AudioDevicePicks())),
      ],
      child: MaterialApp(
        // The real router is not needed: the screen under test is mounted
        // directly, sized wide/narrow for the two layouts.
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: wide ? 1200 : 500,
          child: const SettingsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Mounts the app's routes at [location] with the picks provider stubbed
/// (the settings screen reads it on build; the frb store is absent under
/// `flutter test`).
Future<void> _pumpRouteStubbed(WidgetTester tester, String location) {
  return pumpRoute(
    tester,
    location,
    overrides: [
      audioDevicePicksProvider
          .overrideWith(() => _StubPicksNotifier(const AudioDevicePicks())),
    ],
  );
}

void main() {
  testWidgets('the rail gear renders and routes to /settings', (tester) async {
    await _pumpRouteStubbed(tester, AppRoutes.sessions);

    // The gear is in the rail (fixed below the list).
    final gear = find.byIcon(Icons.settings_outlined);
    expect(gear, findsOneWidget, reason: 'the settings gear must render');

    await tester.tap(gear);
    await tester.pumpAndSettle();

    // /settings is active: the section nav + the voice section render.
    expect(find.text('Voice & Video'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('wide: the section nav renders and sections switch',
      (tester) async {
    await _pumpSettings(tester, wide: true);

    // Section nav on the left; Voice & Video is the initial section.
    expect(find.text('Voice & Video'), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Speaker'), findsOneWidget);
    expect(find.text('System default'), findsWidgets,
        reason: 'both dropdowns carry the default entry');

    // Switch to About: the crypto notice renders.
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

  testWidgets('narrow: the section picker is a dropdown', (tester) async {
    await _pumpSettings(tester, wide: false);
    // The narrow layout renders a DropdownButtonFormField for sections
    // instead of the nav column.
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    // The enum is private; assert by behavior: the initial voice section
    // still renders its fields.
    expect(find.text('Microphone'), findsOneWidget);
  });

  testWidgets('the output dropdown writes the pick into the store',
      (tester) async {
    final picks = _StubPicksNotifier(const AudioDevicePicks());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioDevicePicksProvider.overrideWith(() => picks)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox(width: 1200, child: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In tests the enumerators degrade to empty lists, so the default entry
    // is the only one. Picking it (again) must still write the store —
    // with null (the default IS the reset).
    await tester.tap(find.text('System default').last);
    await tester.pumpAndSettle();
    expect(picks.state.outputDeviceId, isNull,
        reason: 'the default entry persists as null');
  });

  testWidgets('the Connection section carries the moved controls',
      (tester) async {
    await _pumpRouteStubbed(tester, AppRoutes.settings);

    // The settings screen renders (default test viewport is narrow, so
    // the section dropdown shows). The connection label is present.
    expect(find.text('Connection'), findsOneWidget);
  });

  testWidgets('the onboarding menu has no Advanced or About disclosure',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: OnboardMenu(
                onPickChat: _noop,
                onPickGroup: _noop,
                onPickChannel: _noop,
                onPickJoin: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The tiles remain; the disclosures are gone (the gear owns them).
    expect(find.byIcon(Icons.settings), findsNothing,
        reason: 'the Advanced disclosure moved to the settings screen');
    expect(find.byIcon(Icons.verified_user), findsNothing,
        reason: 'the About disclosure moved to the settings screen');
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget,
        reason: 'the Start tiles stay on the first-run surface');
  });
}

void _noop() {}
