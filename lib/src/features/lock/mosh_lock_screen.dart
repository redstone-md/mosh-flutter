// Atomic: biometric-cancel retry UI. ADR 0011 wants fail-CLOSED when there
// is no DEK (no access to encrypted history), but the prior behavior --
// `initMobileDek()`'s `PlatformException` (BiometricPrompt cancel from
// `flutter_secure_storage`'s `read()` with `AndroidOptions.biometric`)
// propagating unhandled through `main()`'s `await`, so `runApp` was never
// reached -- left a blank screen the user could not retry, quit, or
// understand. `main()` now catches ONLY that `PlatformException` and runs
// a `MoshLockScreen` instead; retry re-runs `initMobileDek` (re-prompting
// biometric per ADR 0011), and on success the root swaps to `MoshApp`.
//
// No React equivalent: this is a Flutter-native fail-closed surface. The
// React app loads its DEK over IPC and surfaces a JS error boundary; there
// is no OS biometric prompt in that flow. Keep this comment when editing.
//
// SWAP MECHANISM: hot-swapping `runApp`'s root at runtime is not the
// idiomatic Flutter path. The simplest correct pattern (chosen here) is a
// top-level `ValueNotifier<Widget>` owned by `main()` (see `_appRoot` in
// `lib/main.dart`) that `runApp` mounts via `ValueListenableBuilder`.
// `MoshLockScreen` is constructed by `main()` with the success target
// widget (`nextApp`, the real `const MoshApp()`) and a `swapTo` callback
// that flips the notifier; retry success calls `widget.swapTo(widget.nextApp)`,
// which re-renders the whole tree under the existing `ProviderScope`. This
// avoids widget-tree gymnastics inside `MoshApp`'s router (no
// `Navigator.pushReplacement` from below the `MaterialApp.router`) and
// keeps the lock screen's retry state local to its own `ConsumerState`.
// Picked over a `FutureBuilder` at the root because the retry must own its
// own multi-attempt state (canceled / authenticating / failed) without
// re-creating the widget tree on each attempt. The lock screen takes the
// success target as a constructor arg (rather than importing `MoshApp`)
// so this file has no dependency on `lib/main.dart` and no import cycle.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/platform/mobile_dek.dart' show initMobileDek;

/// Visual state of [MoshLockScreen]. `authenticating` is the spinner shown
/// while a retry is in flight; `canceled` is the rest state after a
/// biometric cancel; `failed` is the defensive state for a
/// non-`PlatformException` DEK error that slipped past the `main()` gate
/// (rare -- `main()` only catches `PlatformException`, so a fail-closed
/// `StateError` or a corrupt Keystore would normally crash `main()`; this
/// branch is belt-and-braces so a future caller of the lock screen can
/// still render rather than blank).
enum LockState { authenticating, canceled, failed }

/// Fail-closed retry UI shown when Android biometric auth is canceled at
/// startup. The `retry` callback defaults to the real [initMobileDek] so
/// the production path re-prompts biometric per ADR 0011; tests inject a
/// controllable fake to stay off the real Keystore. `swapTo` hands the new
/// root widget back to `main()`'s top-level `_appRoot` notifier on
/// success; `nextApp` is the widget to swap in (the real `const MoshApp`,
/// built in `main.dart` so this file stays free of the `main.dart` import).
class MoshLockScreen extends ConsumerStatefulWidget {
  const MoshLockScreen({
    super.key,
    this.retry = initMobileDek,
    required this.swapTo,
    required this.nextApp,
    this.initialState = LockState.canceled,
  });

  /// The DEK-init entry point to (re-)run on retry. Defaults to the real
  /// [initMobileDek]; tests pass a controllable fake that returns a
  /// `Future` they control.
  final Future<void> Function() retry;

  /// Swaps the running app root to `nextApp` on a successful retry. Wired
  /// by `main()` to its `_appRoot` notifier.
  final void Function(Widget next) swapTo;

  /// The widget to swap to on success (the real `const MoshApp`). Passed
  /// in from `main.dart` so this file does not import `MoshApp`.
  final Widget nextApp;

  /// Initial visual state. `main()` enters on a cancel so it defaults to
  /// [LockState.canceled]; tests pump `failed` directly.
  final LockState initialState;

  @override
  ConsumerState<MoshLockScreen> createState() => _MoshLockScreenState();
}

class _MoshLockScreenState extends ConsumerState<MoshLockScreen> {
  late LockState _state = widget.initialState;

  Future<void> _retry() async {
    setState(() => _state = LockState.authenticating);
    try {
      await widget.retry();
      // Success: hand the success target back to main()'s root notifier.
      // The current frame is the lock screen; the swap rebuilds the tree
      // under the existing ProviderScope, so no manual setState is needed
      // (and we deliberately do not setState after the swap -- this widget
      // is about to be unmounted).
      widget.swapTo(widget.nextApp);
    } on PlatformException {
      // Another biometric cancel -- stay on the lock screen. The spinner
      // flips back to the retry UI so the user can try again or quit.
      if (mounted) setState(() => _state = LockState.canceled);
    } catch (_) {
      // Defensive: a non-PlatformException DEK error should NOT have reached
      // here from main() (those propagate), but a future caller or a flaky
      // Keystore could surface one. Show it rather than blanking.
      if (mounted) setState(() => _state = LockState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: switch (_state) {
              LockState.authenticating => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l.lockScreenUnlocking),
                  ],
                ),
              LockState.canceled => _LockBody(
                  icon: Icons.lock_outline,
                  title: l.lockScreenTitle,
                  message: l.lockScreenCanceledMessage,
                  retryLabel: l.lockScreenRetry,
                  onRetry: _retry,
                ),
              LockState.failed => _LockBody(
                  icon: Icons.error_outline,
                  title: l.lockScreenTitle,
                  message: l.lockScreenFailedMessage,
                  retryLabel: l.lockScreenRetry,
                  onRetry: _retry,
                ),
            },
          ),
        ),
      ),
    );
  }
}

/// Shared titled + icon + message + retry layout for the `canceled` and
/// `failed` states (they differ only in icon and message copy). Pulled out
/// so the `build` switch above stays a flat one-branch-per-state read.
class _LockBody extends StatelessWidget {
  const _LockBody({
    required this.icon,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 48),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(retryLabel),
        ),
      ],
    );
  }
}
