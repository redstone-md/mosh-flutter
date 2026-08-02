// M-8 (ADR 0011): widget tests for the biometric-cancel MoshLockScreen.
// The lock screen must NOT call the real `initMobileDek` (which hits the
// Android Keystore) in tests, so a fake retry seam is injected via the
// `retry` constructor param. The swap-to-MoshApp success path is observed
// through a recording `swapTo` callback (the test never mounts the real
// MoshApp, which would pull in the router + frb runtime).
import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/lock/mosh_lock_screen.dart';

void main() {
  testWidgets('canceled state shows title, message, and Retry button',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MoshLockScreen(
            retry: () async {},
            swapTo: (_) {},
            nextApp: const SizedBox(key: ValueKey('mosh-app')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Fail-closed surface is visible: title, explanatory copy, Retry button.
    expect(find.text('Mosh is locked'), findsOneWidget);
    expect(
      find.text(
        'Biometric authentication was canceled. Tap Retry to unlock your '
        'conversations.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    // The spinner is NOT shown in the canceled rest state.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tap Retry transitions to authenticating then swaps to nextApp',
      (tester) async {
    // Controllable fake: completes only when the test resolves the completer,
    // so we can observe the authenticating spinner before success.
    final Completer<void> completer = Completer<void>();
    final List<Widget> swaps = <Widget>[];
    const Key nextAppKey = ValueKey('mosh-app-success');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MoshLockScreen(
            retry: () => completer.future,
            swapTo: swaps.add,
            nextApp: const SizedBox(key: nextAppKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Rest state: Retry button present, no spinner yet.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Tap Retry -> state flips to authenticating. The fake retry is still
    // pending (completer unresolved), so the spinner + "Unlocking Mosh..."
    // must be visible and no swap has happened yet.
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Unlocking Mosh...'), findsOneWidget);
    // The Retry button is replaced by the spinner, so it is gone.
    expect(find.text('Retry'), findsNothing);
    expect(swaps, isEmpty);

    // Resolve the fake retry -> success path swaps to nextApp exactly once.
    // NOTE: do NOT use pumpAndSettle here -- on success the lock screen does
    // NOT call setState (the swap hands the next widget to the root notifier,
    // which is out of this test's tree), so the lock screen would stay in the
    // `authenticating` state with an indefinitely animating CircularProgressIndicator,
    // which pumpAndSettle waits on forever. A plain pump() drains the microtask
    // queue so the swap callback runs; that is enough to assert the swap.
    completer.complete();
    await tester.pump();
    await tester.pump();
    expect(swaps, hasLength(1));
    expect((swaps.single as SizedBox).key, nextAppKey);
  });

  testWidgets('a second biometric cancel stays on the lock screen',
      (tester) async {
    // Fake retry throws a PlatformException on each call (mimics a repeated
    // biometric cancel) so the lock screen must stay on the retry UI.
    int calls = 0;
    final List<Widget> swaps = <Widget>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MoshLockScreen(
            retry: () async {
              calls++;
              throw PlatformException(code: 'cancel');
            },
            swapTo: swaps.add,
            nextApp: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    await tester.tap(find.text('Retry'));
    // The cancel branch DOES call setState (back to `canceled`), so the spinner
    // is replaced by the static retry UI -- pumpAndSettle is safe here.
    await tester.pumpAndSettle();

    // After a cancel, the lock screen is back in the canceled rest state:
    // the Retry button is visible again and no swap happened.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(swaps, isEmpty);
    expect(calls, 1);
  });
}
