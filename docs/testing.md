# Test suite policy

Protect app contracts, error classes and known regressions. A small function,
mock or fake clock is not evidence that a test is redundant. Read implementation
and regression history before deleting; identify tests by file and full group /
test path. Record why loss of each assertion is acceptable and run any claimed
replacement. Keep compiler-only checks and library demonstrations out of the app
suite when they add no app behavior. Do not add tests that merely prove deletion.

Use existing completion futures, streams, scripted pending operations and widget
clock pumps instead of sleeping until something probably happened. Preserve time
assertions when deadlines, backoff or expiry are the actual contract. Keep live
network/native tests in their explicit native/integration runners; keep benchmarks
out of ordinary unit tests. Never increase global timeouts to hide failures.

## CI guard

`python3 scripts/test-policy.py` uses only Python and Git. No existing configured
linter covers these gaps: Flutter uses `flutter_lints`, Rust uses Clippy, and the
Node scripts have no ESLint setup. Keep those linters for semantic/type checks.
The guard has executable examples in `scripts/test_test_policy.py` and a separate
cheap CI job. It always rejects `test/it/describe/group.only` and `only: true` /
`solo: true`, including historical occurrences. Do not alias test entry points to
evade the guard.

New skip/todo/ignore annotations, test timeout/retry overrides (including
`Future.timeout` and `Stream.timeout` calls), and real delays
require a reason and tracking issue on the same or immediately preceding line:

```dart
// test-policy: timeout https://linear.app/ivoxygen/issue/IVO-123/example -- real peer negotiation has a bounded external deadline
```

Use the appropriate category (`skip`, `timeout`, `retry`, `wait`) and an actual
Linear issue URL or historical GitHub issue URL. Focus cannot be exempted. Scope
exceptions to the exact operation; no file-wide suppressions. For a skip, also
retain the runtime reason/platform predicate. An issue link is accountability,
not permission to hide a useful flaky regression. Fix determinism first.

The guard freezes existing hazardous expressions and their multiplicity **per
file** at `3b2b88eb9fc49081be28b98c375c52fd7948adae`. Changing a delay or
timeout's value, duplicating an expression or moving it into another file requires
review and an exception. Removing an occurrence does not raise a global allowance. Counts do not track
test identity: the same historical expression can be reintroduced within its
original file. Review moves and reintroductions explicitly.
The baseline is not advanced per PR. Existing native-library gates, subprocess
entry points, live-relay gates and real-protocol deadlines remain runnable under
their original conditions; they do not gain invented tracker links. Historical
waits without issues are retained debt, not approved patterns for new tests.

Scope: Dart test/support, native and integration trees; Node/Python script test
files; Rust `tests/` and files with `test` in their stem under `mosh-core/` and
`mosh-media/`. Production, vendor and Moss sources are excluded. This lexical guard
does not parse arbitrary aliases, computed options or Rust tests embedded in
ordinary production modules. Review those manually, including runtime `return`
gates: a green runner can otherwise hide a test that never asserted anything.
It does not decide whether a test has value. Missing baseline history fails the
check; CI checks out full history. Run the guard examples with:

```sh
python3 -B -m unittest discover -s scripts -p test_test_policy.py
```

## Keep process startup proportional to the work

Short related unit libraries can share a `*_test.dart` entry point. Keep their
case declarations and private fixtures in sibling `*_cases.dart` libraries;
register each synchronous `main` with `group('module', module.main)`. This scopes
setup/teardown to the original module. The policy guard requires exactly one such
runner per case library, so renaming a file cannot silently remove its tests.
Use `flutter test path/to/module_cases.dart` to debug one case library directly.

Group by feature and bounded runtime, not into one giant serial suite. Preserve
separate processes for native initialization/fallback probes, actual HTTP and
process-global contracts. A shared binding can change HTTP behavior even when
all tests only import Flutter packages. Existing waits/skips are still subject
to the baseline policy when moving a file; grouping does not exempt them.

Prefer exact required frames over unbounded settling when the frame contract is
known ([Flutter pumpAndSettle documentation](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html)).
For real async work, await the readiness/completion future inside `runAsync`
instead of sleeping ([Flutter runAsync documentation](https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html)).
Create completion futures in that real zone before triggering the operation;
a fake-zone Completer can delay delivery even when its callback has fired.
Do not globally disable motion or fast-forward real network/hardware behavior to
make a runtime metric look better.

Image tests can start loading and await `precacheImage` inside `runAsync`, then
pump the loaded or error UI. Awaiting a decode that already started in the fake
zone can deadlock. Use the widget's actual `Image.image`, including resize and
validation wrappers. Keep success/fallback assertions: completion includes load
failure. If initial rendering is the contract, observe the first layout frame
before waiting; retain cache-hit checks immediately after reopening. See the
[stability audit](Proposals/flutter-attachment-stability-test-cleanup.md).
The [attachment preview audit](Proposals/flutter-attachment-preview-test-cleanup.md)
records this replacement for fixed decode sleeps with real files and codecs.

The [runtime audit](Proposals/flutter-test-runtime.md) records the startup-cost
experiment, preserved case identities and the measured full-run comparison.

For standalone widgets, import `test/support/pump.dart` and use `pumpScreen`.
Tests that navigate through the production routes import `pump_route.dart` and
use `pumpRoute`. Both share the provider/frame implementation in `pump_scope.dart`.
Keep route imports and re-exports out of the screen helper so a leaf test does
not need the entire application graph. Actual route tests keep the real router.

For widget matrices, identify which code actually combines the dimensions.
When interaction code is shared, cover its platform branches and each screen's
wiring without automatically multiplying every kind by every platform. Retain
combinations with distinct behavior or regression evidence. Prefer an existing
component harness for shared interactions; keep real screen/route tests for
navigation, provider wiring, permissions and mounted state.

For layout matrices, seed unrelated preferences through the existing harness
before mounting instead of repeatedly changing them through application state.
Keep dedicated preference-change tests and independently restored starting
states when layout depends on navigation history. The
[first-run viewport audit](Proposals/flutter-first-run-viewport-fixture.md)
checks geometry and saved state before applying this fixture change.
