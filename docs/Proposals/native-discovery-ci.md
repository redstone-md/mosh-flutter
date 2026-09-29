# Native discovery CI correction

PR [29](https://github.com/redstone-md/mosh-flutter/pull/29), 2026-09-29.
The user held publication of the verified OpenMLS review fixes until the
failed native CI checks were investigated and corrected.

## Evidence

[Run 36483166048](https://github.com/redstone-md/mosh-flutter/actions/runs/36483166048)
failed the Windows public-bridge pairing flow and the macOS public-bridge DM
flow. Rerunning only the failed jobs on the unchanged head `5049a302` failed
both again. Other core suites passed in those jobs.

The affected tests use independent native processes and automatic public
Moss discovery. Their network snapshots included hundreds of unrelated peers
and relay paths between processes on the same host. Local repetitions also
failed at different stages, including the initial two-party DM handshake,
delivery after restart and offline recovery. These failures cannot all be
attributed to one application state transition.

A temporary timing probe measured 10.66 seconds in `OpenStream` while the
device-link service held its lock. `SendStream` already starts the SDK's
reader. Removing the redundant lookup improves command responsiveness, but
did not make repeated public-network tests reliable. The timing probe was
removed after diagnosis. QR payloads and confirmation codes were removed
from the pairing timeout diagnostic.

The first full isolated run passed 413 unit tests, then one child failed
startup with Moss listen error -13. Default SDK Masq chooses an ephemeral TCP port
before binding UDP on the same number. That UDP port can already be occupied.
The old shared-node fallback handled only a requested nonzero port, and did
not reallocate after an ephemeral bind collision.

A later full run reached public pairing but failed discovery after prior
scenarios shared one tracker network. The real tracker retains addresses for
20 minutes. A temporary probe counted 34 advertised addresses in one suite.
Giving each scenario its own network id reduced those lists to that scenario's
processes. The configuration regression for independent scenario networks
failed before this correction; all five config tests now pass.

The first corrected [run 36501886326](https://github.com/redstone-md/mosh-flutter/actions/runs/36501886326)
passed both Rust jobs: Windows completed 418 unit and 30 integration tests;
macOS completed 419 unit and 30 integration tests. Both retained 13 ignored
entries. Flutter, binding drift, macOS preflight, Android APK and both desktop
packages also passed. The remaining Windows native UI step still used public
discovery and failed to reach `Device linked` after approval within 40 seconds.
Its local public-network run passed in 39 seconds; the same test with the
loopback tracker passed in 7 seconds. The UI step now uses that tracker too.

[Run 36506447520](https://github.com/redstone-md/mosh-flutter/actions/runs/36506447520)
again passed eight of nine jobs, including both complete Rust suites. The
isolated Windows UI completed initial linking and revocation, then failed
fresh linking of the revoked peer with `Connecting` / `ConnectionLost`.
Closing the peer also timed out. The test helper's stdout reader paused
between JSON requests. A real subprocess regression reproduced a full output
pipe preventing the peer from progressing, then passed after continuous
draining. This establishes a helper defect; the next Windows run must verify
whether it explains that runner's linking failure.

That Windows job spent 590 seconds building the desktop app, 249 seconds
building the native library and 172 seconds in setup. The UI step took 81
seconds. The successful debug build cache was not saved because the later
test failed. The approved CI split removes the desktop build and prerequisite
job wait from native linking feedback, while keeping desktop integration.

[Run 36512077773](https://github.com/redstone-md/mosh-flutter/actions/runs/36512077773)
completed native linking feedback in 11 minutes 34 seconds, starting alongside
the first jobs. Both subprocess pipe regressions passed on Windows. The UI
still failed fresh linking at the same phase, so the pipe correction does not
explain that failure. Setup took 164 seconds, Rust library build 222 seconds,
independent-process checks 90 seconds, the first Flutter test 127 seconds and
the UI step 64 seconds. Cargo cache save was still skipped on failure despite
the trusted-PR `save-if`; `cache-on-failure` is now enabled with that restriction.
The next diagnostic run records Moss session events through the existing
`MOSH_DEBUG_RECORD_DIR` seam and captures only phase/error/authorization flags
from the independent peer on fresh-link failure. Records contain network
metadata, not QR values, codes or encrypted installation databases.

## Changes

- Device linking and DM request peer discovery through the existing
  `ConnectToPeer` path, then send with `SendStream`. Protocol retries and
  durable acknowledgements remain unchanged.
- Shared-node startup reallocates after a bind failure, including auto-port
  collisions, with at most three attempts. It returns other errors immediately
  and returns the final bind error when allocation is exhausted. This retries
  socket allocation, not failed tests or protocol operations.
- `scripts/moss-test.mjs` starts a real WebTorrent `bittorrent-tracker` 11.2.3
  server on `127.0.0.1` and a random port. It runs Cargo, propagates its exit
  status and closes the server. Signal cleanup terminates the owned process
  tree. The test tool installs outside the repository and app manifests.
- The tracker uses its public filter hook to treat Moss's literal
  `event=none` as a regular announce. No Moss source is modified.
- A private debug-only `MOSH_TEST_TRACKER_URL` config override accepts only
  loopback HTTP `/announce` URLs with an explicit nonzero port and no
  credentials, query or fragment. Existing SDK `trackers` and `network_id`
  options isolate discovery. Public DHT, LAN and NAT mapping are disabled
  only in that network.
- The fixture assigns a random u64 `MOSH_TEST_NETWORK_SCOPE` per scenario,
  passes it to all independent installations and preserves it across restart.
  The scope separates tracker discovery between scenarios without changing
  process-global environment variables. It is ignored without the test tracker.
- The Windows and macOS Cargo jobs use the wrapper. The independent-process
  linking step and Flutter Devices UI in the Windows native lane use it too.
  The wrapper's `--native-ui` mode runs the existing Flutter test, including
  its real Rust library and independent peer. Public bridge cases
  still discover each other automatically, without manual peer connections.
- Test assertions, deadlines, ignore lists and protocol retry budgets are
  unchanged. Private test names now describe Moss discovery without claiming
  that every run uses the public defaults.
- Native UI timeout diagnostics include only the real phase and error kind,
  without QR payloads or confirmation codes. The 40-second deadline is unchanged.
- `NativePeer` continuously drains child stdout, discards background log lines
  and buffers JSON replies between requests. Cancelling the reply iterator
  cancels its upstream subscription. The subprocess lifecycle is unchanged.
- Native device linking has its own Windows job, independent of desktop app
  compilation and the three prerequisite jobs. It builds the real Rust library
  and peer, runs both independent-process suites, checks the pipe regression
  and exercises the Devices UI. The desktop slice-one job keeps its build and
  integration test.
- The desktop job saves its debug Cargokit cache immediately after a successful
  build. The shared setup saves Cargo dependency caches on main and PRs from
  this repository; fork PRs cannot save them. Native linking uses the same
  `desktop` cache namespace as the Windows Rust job.

Without the override, config bytes remain unchanged. Release builds do not
compile the override. No public Rust API, bridge binding, application
dependency, database schema or wire format changes.

## Checks

- New configuration regressions failed before implementation, then passed.
  They verify isolation, preservation of unrelated node settings, rejection
  of remote/malformed URLs and byte-identical default configuration.
- Auto-port collision, collision after fixed-port fallback and bounded
  exhaustion regressions failed against the old allocation policy. The
  six shared-node tests now pass, including the existing occupied-port test
  against the real SDK and immediate propagation of non-bind errors.
- Each originally failing public-bridge scenario passed five consecutive
  runs with the local tracker. Pairing took 1.28 to 1.35 seconds; DM took
  8.24 to 12.76 seconds, including primary-off delivery and restart.
- The offline pairing responsiveness test passes. It also passed on the old
  code, so it freezes the cancellation/latency contract rather than proving
  reproduction of the original CI failure.
- The full wrapped command passed 419 unit tests and 30 integration tests,
  with 13 existing ignored entries. It includes pairing, restart, primary-off
  delivery, offline recovery, history transfer and revocation.
- Build, release-library check, strict all-target Clippy, rustfmt, Node syntax,
  `git diff --check` and actionlint passed.
- The wrapper preserves Cargo exit 101 and closes its tracker after a failing
  command or spawn error. SIGTERM terminates its owned native process tree
  and closes the tracker; interruption returns a nonzero exit status.
- V8/c8 measured the updated wrapper at 90.67% line coverage and 76.31% branch coverage.
  Checks exercised fresh tool installation, automatic native discovery,
  malformed tool metadata, Cargo failure, spawn failure and interruption,
  plus native UI execution and rejection of extra UI-mode arguments.
  Windows cleanup branches require the Windows runner.
- LLVM coverage of measured changed runtime lines is 75/83, 90.36%, from the
  config and startup unit tests plus both real public-API scenarios. The
  debug network module reached 100% line coverage. Stable Rust does not export
  branch counters, so no Rust branch percentage is claimed.
- The real stdout-flood subprocess regression failed before the reader fix,
  then passed. A second case verifies the existing error on EOF before a reply.
  The full native Devices UI also passed locally in 7 seconds after the fix.
- Direct Dart VM coverage measured 10/10 changed helper runtime lines and
  4/4 SDK-reported changed branch counters. These are changed-code counts,
  not whole-helper coverage. Flutter analysis and formatting passed.
- Windows/macOS validation runs in GitHub Actions after publication; the local
  checks above ran on Linux.

The inherited `moss_ffi.rs` exceeds the repository's file-size limit. The
override lives in a separate module; its new helpers and tests are below the
function limit. The existing FFI loader and native end-to-end test structure
retain their boundaries.

## Standards

Source review of the initial 17 CI files, the six-file native UI follow-up and
the eight-file pipe/CI split follow-up found no documented breaches or
substantive heuristic smells. The changes
retain module boundaries, existing dependencies and contracts. The inherited
file-size exception is documented. Findings: 0.

## Spec

Scenario scope reaches every child and survives restart. The private override
affects only debug tracker networks. Automatic discovery and real native
dependencies, protocol acknowledgements and shared-node ownership remain in
place. The six-file native UI follow-up preserves the real bridge, independent
peer, assertions and deadline. The eight-file pipe/CI split follow-up preserves
those checks and adds two real subprocess cases. All three reviews found no
missing requirement or unrequested public contract change. Actionable findings: 0.

## Limits and reproduction

The local network proves native automatic discovery, pairing, MLS delivery,
restart and storage behavior. Public tracker, NAT and relay availability
still need live-network probes. Physical Android acceptance remains pending
because the user's device cannot connect to this server. Issue 28 remains open.

From the repository root:

```bash
node scripts/moss-prepare.mjs
cargo build --manifest-path mosh-core/Cargo.toml
node scripts/moss-test.mjs
flutter test native_test/native_peer_io_test.dart
node scripts/moss-test.mjs --native-ui
```

For a live public-network probe, omit the wrapper and ensure the test override
is unset:

```bash
cargo test --manifest-path mosh-core/Cargo.toml --test device_link_flow --test multi_device_dm_flow public_bridge
flutter test native_test/device_link_test.dart
```

The runtime boundary is documented in [ADR 0029](../ADR/0029-private-desktop-device-linking.md),
and the CI network in [ADR 0015](../ADR/0015-deep-link-and-ci-and-versioning.md).

## Changed files

- `.github/workflows/ci.yml`
- `.github/actions/setup/action.yml`
- `scripts/moss-test.mjs`
- `mosh-core/src/moss_ffi.rs`
- `mosh-core/src/moss_ffi/test_network.rs`
- `mosh-core/src/device_link/transport.rs`
- `mosh-core/src/private_dm_runtime/transport.rs`
- `mosh-core/src/shared_node.rs`
- `mosh-core/tests/device_link_flow.rs`
- `mosh-core/tests/multi_device_dm_flow.rs`
- `mosh-core/tests/link_support/mod.rs`
- `native_test/device_link_test.dart`
- `native_test/support/native_peer.dart`
- `native_test/native_peer_io_test.dart`
- `native_test/support/stdout_flood.rs`
- `docs/ADR/0015-deep-link-and-ci-and-versioning.md`
- `docs/ADR/0026-one-node-a-transport-seam-and-a-dm-outbox.md`
- `docs/ADR/0029-private-desktop-device-linking.md`
- `docs/ADR/0030-linked-desktop-dm-clients.md`
- `docs/Features/device-linking.md`
- `docs/Features/private-dm.md`
- `docs/Proposals/native-discovery-ci.md`
- `docs/Proposals/openmls-review-corrections.md`
