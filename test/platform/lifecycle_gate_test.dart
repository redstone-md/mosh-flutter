// Foreground-gate unit test (ADR 0011 follow-on). Drives the
// `@visibleForTesting` `handleLifecycleState` method directly -- the
// state-transition body extracted from `didChangeAppLifecycleState` -- so
// the test is deterministic and does NOT depend on binding-internal
// lifecycle-dispatch APIs (which vary across Flutter test hosts). This is
// the simpler/deterministic approach the brief prefers over pumping a
// frame and dispatching `AppLifecycleState.resumed` via the binding.
//
// Completion is asserted via the `@visibleForTesting` `isCompleted` getter
// (synchronous) instead of an async `completes` matcher: a never-completing
// future under `isNot(completes)` would block the matcher until its
// timeout, so the cold-start (incomplete) assertion is checked via
// `isCompleted` to keep the test fast and deterministic. The post-resumed
// assertion `await`s `waitUntilResumed()` (which completes synchronously
// once `handleLifecycleState(resumed)` has run).
//
// The constructor registers the gate as a `WidgetsBindingObserver` and
// reads `WidgetsBinding.instance.lifecycleState` for the best-effort fast
// path, so the test runs inside `testWidgets` (which initializes
// `TestWidgetsFlutterBinding`) so `WidgetsBinding.instance` is non-null.
// The cold-start simulation: under `flutter test` the binding's initial
// `lifecycleState` is null (no `resumed` has been dispatched), so the
// fast path does NOT fire eagerly -- mirroring a real cold start where
// `lifecycleState` is null before the first frame. The observer
// transition (driven here via `handleLifecycleState`) is the primary
// mechanism under test.

import 'package:flutter/material.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/main.dart' show LifecycleGate;

void main() {
  testWidgets(
      'LifecycleGate: incomplete cold start, completes on resumed, idempotent',
      (tester) async {
    // Cold-start simulation: construct the gate. The binding's
    // `lifecycleState` is null under `flutter test` (no resumed has been
    // dispatched), so the best-effort fast path does NOT complete the
    // completer eagerly -- the observer transition is the primary signal.
    final LifecycleGate gate = LifecycleGate();
    expect(gate.isCompleted, isFalse,
        reason: 'cold start: completer must not be completed before resumed');

    // Non-resumed transitions must NOT complete the gate: inactive/paused
    // transitions are common on Android and must not release the guard.
    gate.handleLifecycleState(AppLifecycleState.inactive);
    expect(gate.isCompleted, isFalse,
        reason: 'inactive must not complete the gate');
    gate.handleLifecycleState(AppLifecycleState.paused);
    expect(gate.isCompleted, isFalse,
        reason: 'paused must not complete the gate');

    // The first `resumed` completes the completer synchronously.
    gate.handleLifecycleState(AppLifecycleState.resumed);
    expect(gate.isCompleted, isTrue, reason: 'resumed must complete the gate');

    // `waitUntilResumed()` resolves once completed (it completes
    // synchronously on handleLifecycleState(resumed)).
    await gate.waitUntilResumed();

    // A second `resumed` is a no-op (idempotent): the completer is already
    // completed, so re-dispatch does not throw (Completer.complete guards).
    gate.handleLifecycleState(AppLifecycleState.resumed);
    expect(gate.isCompleted, isTrue, reason: 'second resumed is idempotent');
    await gate.waitUntilResumed();
  });
}
