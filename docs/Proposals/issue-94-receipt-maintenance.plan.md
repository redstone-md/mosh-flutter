# Issue 94: receipt commands must not service every saved DM

The owner `callers-20261024-171047` export selects PID 3792 and matches all
five binaries of `cpu-20261024-153156` / runtime `82cc774e`. Its 8,940 selected
weights include 246 under the DM mark-viewed command and 158 under its tick.
Strict verification is down to 14 weights, versus 341 in the prior export.
These are overlapping sample observations, not CPU milliseconds or a causal A/B.

There are 853 excluded foreign weights and 3,514 weights with broken unwinds.
The caller/raw instruction totals differ by four; Moss leaf RVA counts also
do not match exactly. Preserve these limits rather than claiming conservation
between distinct exports. The raw ETL remains private on the owner's machine.

## Scope and candidate selection

- First reproduce the disabled mark-viewed command querying the full mesh once
  per invocation, using the existing real-state-machine MemoryNet counters.
- Check the persisted receipts answer before draining/ticking every DM. Missing,
  explicitly disabled and malformed answers retain their existing off semantics.
- For enabled commands, receive inbound frames and send the target chat's
  receipts without ticking every saved chat's timers, outbox and media.
  Preserve encrypted receipts, failed-send retries, events and authorization.
- Keep ordinary service/poll ownership and cadence. The existing background
  thread still services the runtime without a receipt command.
- Keep the two mesh reads in list/poll operations: the latter observes routes
  after maintenance. No TTL cache or freshness change is included.
- Leave identity/ownership construction for a separately measured correction.
- No public API, wire/storage/dependency, Flutter or Moss source changes.

Opportunity: impact 2 / confidence 5 / effort 2 = 5. This removes incidental
maintenance; whole-Windows gains are expected to be limited. One current stack
enters the inner receipt iterator, so enabled behavior needs coverage as well;
the exact persisted answer over the complete recording is not established.

## Checks

Run the regression red first, then verify no mesh reads for repeated disabled
commands and continued independent service. Keep default/off privacy, enabled
delivery/read settlement, failed receipt retries and restart tests green.
Exercise the public conversation API through the existing independent process
driver. Compare twenty alternating release pairs using the same restored
fictional offline fixture, normal background service and identical network
isolation, checking complete message/identity/permission outputs.

Run formatting, build, focused/full Rust and Clippy, independent review,
CodeAnt comments/nitpicks and platform CI before handing over a configured
Windows release. No merge or release is authorized.
