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

New skip/todo/ignore annotations, test timeout/retry overrides, and real delays
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
