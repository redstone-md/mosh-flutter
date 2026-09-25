# mac-stability — plan

Brainstorm: `mac-stability.brainstorm.md` (chosen: K1-B self-signed cert,
V1-A CallMedia hub, V1b skip SendStream, V2 primed ring, P3 direct-only
stream + backoff, P1/P2 freshness keepalive, P4 Rust service thread + Dart
per-kind guard, P5 transition logs).

## Goal

1. macOS asks for the keychain password once per install, not twice per launch.
2. Voice frames never wait on the DM mutex or the DM tick.
3. Playback absorbs normal network jitter (60 ms playout delay).
4. Serving a file can no longer block the runtime for seconds per chunk.
5. Connected/Offline reflects authenticated contact and does not flap.
   The outbox sends whenever MLS allows.
6. The DM protocol runs without the UI poll.
7. Logs record real state changes and real MLS error causes.

## Scope

In: `mosh-core` DM runtime, call media, playback; Dart auto-poll; macOS
packaging script + workflow + signing docs.
Out: see the brainstorm's "Out of scope".

## Constraints and risks

- The FFI surface stays unchanged (`call_send_frame` / `call_drain_frames`
  keep their signatures), so no codegen is expected. If it changes: rerun
  codegen and commit.
- Never run `cargo test` and `flutter test` at the same time: they share one
  redb.
- The signing change can only be proven on macOS: a CI run for the
  signature, a real Mac for the prompt. The keychain claim stays "expected"
  until then.
- Keepalive: one extra MLS frame every 10 s per connected session.
- Loss detection goes from 5 s to 25 s.
- `private_dm_runtime.rs` is already over `file_max_loc`. New code goes to new
  modules (`call_media.rs`), not into it.

## Testing methodology

- Rust state and outbox behaviour: two real runtimes on the in-memory
  transport (`MemoryNet`), driven through the public runtime API, judged by
  snapshots and the frames that crossed. The clock is passed to `tick`, so
  windows are crossed by arithmetic, not by sleeping.
- New `MemoryNet` capability: a "gossip-only" link that delivers frames but
  reports no `peer_details` row. This is the exact field condition for P1/P2.
- Call media: a two-runtime test sends frames both ways while a test thread
  holds the runtime busy, and proves the frames still flow through the hub.
- Playout: renderer unit tests on a real ring (no device): silence until
  primed, plays once primed, re-primes after an underrun, trims the backlog to
  the target.
- Dart: `auto_poll_provider_test` proves one stuck kind does not stop the
  others.
- Quality bar: every changed behaviour has a failing-first test. Tests assert
  what the caller sees, not internals. No mocks beyond the existing
  `MemoryNet` and `ScriptableGateway` seams.

## Steps

0. [x] Baseline: `cargo test` (mosh-core), then `flutter test`, then
   `flutter analyze`. Record failures below.
1. [x] **P3 blob route.** Test: with a relayed or unknown peer, chunks go to
   the room wire and `send_to_peer_stream` is never called. After a stream
   failure, the next chunks inside 10 s skip the stream. Implement the
   Direct-only choice once per request, the 10 s backoff field, and the
   comment fix. Done: tests green.
2. [x] **P5 logs.** Test: `note_authenticated_frame` on an already Connected
   session writes no "session connected" line; the transition writes one.
   Hello decrypt failure includes the error. Done: tests green.
3. [x] **P1/P2 reachability.** Tests first:
   (a) a gossip-only link keeps Connected for more than 25 s while keepalives
   cross;
   (b) no authenticated frame for 25 s drops to Handshaking, and one frame
   brings it back;
   (c) the outbox sends over a gossip-only link;
   (d) a keepalive Hello goes out every 10 s while Connected.
   Implement `last_authenticated_rx_ms`, the keepalive in `pump_hello`, the
   freshness-based loss, and drop `unreachable_since_ms` / the reach gate.
   Update the old window test. Done: state and outbox suites green.
4. [x] **V1 CallMedia.** Tests first:
   (a) frames cross between two memory runtimes through the hub;
   (b) own-direction frames are dropped;
   (c) frames for an ended call are dropped;
   (d) send and drain work while another thread holds the runtime mutex.
   Implement `call_media.rs`, `DmTransport::drain_media`, the media inbox
   claim, the runtime sync, and the API cache. Remove the frame queue from
   `CallState`. Update the inbound filter test. Done: tests green; the ignored
   moss call test still compiles.
5. [x] **V2 playout.** Renderer tests first (primed, underrun re-prime,
   trim). Implement. Done: tests green.
6. [x] **P4 service thread + Dart guard.** Rust: `service_loop` started once
   with the runtime (500 ms). Test: the loop body drives a handshake with no
   poll call. Dart: per-kind in-flight guard, with a test where one kind
   hangs. Done: both suites green.
7. [x] **K1 signing.**
   - `scripts/macos-signing-cert.sh` makes a self-signed code-signing
     certificate and p12 once, prints the secret values, and keeps the key
     out of the repo.
   - `macos-package.sh` signs inside-out with `MOSH_SIGN_IDENTITY` when set,
     ad-hoc otherwise.
   - The workflow imports the p12 into a temporary keychain when the secret
     exists.
   - `CODE_SIGNING.md` and README: explain it and say plainly that
     Gatekeeper still warns.
   Done: `bash -n` passes; a CI run on the branch shows the signature once
   the secrets exist.
8. [x] Docs: `docs/Architecture.md` (call media path, reachability), the
   CHANGELOG `Unreleased` entry.
9. [ ] Final validation (below). Then commit, push, and open the PR
   (the push and the PR wait for the maintainer's go-ahead).

## Baseline failures

Baseline on `d01d0b7`: `cargo test` 362 passed, 0 failed. `flutter test`
first failed in two ways, and both came from stale local build output, not
the code:

- [x] 76 files failed to load with `settingsGearLabel isn't defined`. Cause:
  the gitignored `lib/l10n/app_localizations*.dart` were stale. Fix:
  `flutter gen-l10n`. After that the suite was green.
- [x] `test/gateway/real_bridge_dispatch_test.dart` failed in setUpAll with a
  content-hash mismatch. Cause: a stale
  `mosh-core/target/release/mosh_core.dll`. Fix:
  `cargo build --release --manifest-path mosh-core/Cargo.toml`.

## Outcome notes

- Step 7 (signing) is verified only as far as this Windows host allows.
  `bash -n` passes on all three scripts. A dry run of the certificate
  script gives a code-signing certificate and a SHA1/3DES p12. The CI
  import, the codesign run and the keychain behaviour still need the repo
  secrets plus one CI run and one real Mac (install, then update).
- V1b (SendStream for voice) was skipped on purpose; see the brainstorm.
- Found during step 5: the Dart jitter buffer waited for a lost frame
  until 9 frames queued (180 ms), longer than playback holds. Lowered to
  3 frames, the same as the playout delay.

## Final validation (in order)

1. `cargo fmt --manifest-path mosh-core/Cargo.toml` — formatting gate.
2. `cargo clippy --manifest-path mosh-core/Cargo.toml --all-targets -- -D warnings` — lint gate.
3. `cargo test --manifest-path mosh-core/Cargo.toml` — the full Rust suite.
4. `dart format lib test integration_test` — formatting gate.
5. `flutter analyze` — the Dart analyzer.
6. `flutter test` — the full Dart suite (never at the same time as cargo test).
7. `flutter_rust_bridge_codegen generate` + `git diff --exit-code` — proves no
   FFI drift.
