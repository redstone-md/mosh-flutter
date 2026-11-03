// M-8 (ADR 0011): widget tests for the biometric-cancel MoshLockScreen.
// The lock screen must NOT call the real `initMobileDek` (which hits the
// Android Keystore) in tests, so a fake retry seam is injected via the
// `retry` constructor param. The swap-to-MoshApp success path is observed
// through a recording `swapTo` callback (the test never mounts the real
// MoshApp, which would pull in the router + frb runtime).
import 'dart:async' show Completer;

// `hide LockState` resolves the same ambiguous-import clash main.dart
// fixes: `package:flutter/material.dart` (via `shortcuts.dart`) re-exports
// a Flutter `LockState`, and the lock screen defines its own `LockState`.
// The insecureDevice test references `LockState.insecureDevice`, so hide
// Flutter's from the material import.
import 'package:flutter/material.dart' hide LockState;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/lock/mosh_lock_screen.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('canceled state shows title, message, and Retry button',
      (tester) async {
    await pumpScreen(
        tester,
        MoshLockScreen(
          retry: () async {},
          swapTo: (_) {},
          nextApp: const SizedBox(key: ValueKey('mosh-app')),
        ),
        settle: false);
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

    await pumpScreen(
        tester,
        MoshLockScreen(
          retry: () => completer.future,
          swapTo: swaps.add,
          nextApp: const SizedBox(key: nextAppKey),
        ),
        settle: false);
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

    await pumpScreen(
        tester,
        MoshLockScreen(
          retry: () async {
            calls++;
            throw PlatformException(code: 'cancel');
          },
          swapTo: swaps.add,
          nextApp: const SizedBox(),
        ),
        settle: false);
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

  // BIOMETRIC_UNAVAILABLE: the device has no enrolled PIN/pattern/password/
  // biometric. main() branches on error.message containing
  // BIOMETRIC_UNAVAILABLE to pump MoshLockScreen with
  // initialState: LockState.insecureDevice. This state is NOT retry-
  // recoverable (re-prompting cannot mint a Keystore key without a device
  // credential), so the body is message-only -- the title + message
  // render, but there is NO Retry button and NO spinner. ADR 0011
  // fail-closed holds: no DEK = no history access; the UI just tells the
  // user to set a screen lock. There is no Open Settings button
  // (android_intent_plus / url_launcher are not deps; a Settings
  // deep-link is a documented follow-up), so there is nothing platform-
  // channel to fake here.
  testWidgets('insecureDevice state shows title + message, no Retry button',
      (tester) async {
    await pumpScreen(
        tester,
        MoshLockScreen(
          // initialState is the only thing this test exercises: main()
          // pumps this state directly on BIOMETRIC_UNAVAILABLE. retry is
          // never called (no button to tap), so the default
          // initMobileDek seam would be safe -- but a throwing fake is
          // passed anyway so a future refactor that adds a button
          // cannot silently hit the real Keystore from this test.
          retry: _insecureDeviceNoRetry,
          swapTo: _insecureDeviceNoSwap,
          nextApp: SizedBox(),
          initialState: LockState.insecureDevice,
        ),
        settle: false);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // The insecure-device surface is visible: title + explanatory copy.
    expect(find.text('Device not secured'), findsOneWidget);
    expect(
      find.text(
        'Mosh requires a screen lock (PIN, pattern, or biometric) to '
        'protect your conversations. Set one in Settings - Security, then '
        'reopen Mosh.',
      ),
      findsOneWidget,
    );
    // NOT retry-recoverable: no Retry button, no spinner.
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

// Fakes for the insecureDevice test. retry is never invoked (no Retry
// button in this state), but if it ever were, failing the test is better
// than silently hitting the real Android Keystore via initMobileDek.
Future<void> _insecureDeviceNoRetry() async {
  throw StateError(
    'insecureDevice retry must not be invoked -- the state is not '
    'retry-recoverable',
  );
}

void _insecureDeviceNoSwap(Widget next) {
  throw StateError(
    'insecureDevice swapTo must not be invoked -- the state is not '
    'retry-recoverable',
  );
}
