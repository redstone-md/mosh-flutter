# mosh — remaining bugs (to fix)

Bug hunt 2026-06-17. Fixed (with tests): **#1** voice nonce reuse, **#2** group drain abort, **#3** group commit dedup, **#4** invite fingerprint parsing, **#9** unread by fingerprint, **#11** Range overflow, **#19** CallEnd classification, **#16** recorder double-stop, **#20** offered-set reset across conversations, **#22** snapshot-corruption → Result, plus LOW frame-crypto seq-overflow guard, DiagnosticsDrawerHelpers nested-detail, invite.rs DM fingerprint validation, use-modal-focus ancestor aria-hidden/inert, secure_storage cache-only-on-success.

Documented (no behavior change): **#23** `add_peer` — correct for its only callers (2-party DM); added a 2-PARTY-ONLY doc contract so a future multi-party caller doesn't reuse it. Returning `commit_bytes` would be dead surface the sole caller ignores.

Round 5: **#5** overlapping voice poll drains (in-flight `draining` guard), **#6** voice setup/teardown ref race (`cancelled` check after each setup await + stop the handle), plus extracted `drainCallFrames` into its own module — that drain logic is unit-tested (`call-drain.test.ts`); the in-flight guard and cancelled-after-await are lifecycle fixes covered by reasoning + typecheck (a full hook test needs fake-timers + AudioContext/MediaStream mocks). LOW **ciphertext_store** skip-bad-lines (one torn JSONL line no longer bricks the whole history).

Round 7: added a fake Web Audio / WebCodecs test harness (`fake-web-audio.ts`), then fixed **#15** ringtone leak (oscillator stop backstop + close-once on ended), **#13** playback latency resync (cap drift after a stall), **#12** gap-aware decoder timestamps (`pushFrame(seq, frame)`, timestamp from masked seq so dropped frames aren't pretended contiguous). All three unit-tested against the harness.

Round 6: **#17** message_id collision — new `adapters/message_id.rs` `MessageIdGen` (monotonic per-session `{ms}-{seq}`, `Cell` keeps `stamp_message` `&self`), wired into DM/group/channel. Unit-tested (`message_id` tests). The `len()`-based id is gone, so a same-ms double-stamp can no longer collide. (The persist-tail `{ts}-{idx}` fallback is untouched — it only fires for id-less messages, which is now rare since every stamped message gets a counter id.)

False positives: **#14** (jitter-buffer, see below). **#10** — `sendNotification` is synchronous (`void`, not a Promise), so there is no async rejection to swallow; the existing try/catch was already correct. The tsc error on the attempted `.catch` is what surfaced it. Kept the tested `notificationBody` extraction from that pass.

Won't-fix: **formatBytes TB** — attachments cap at 50 MB, so GB is already the ceiling; TB is unreachable (YAGNI). Everything else below is outstanding.

Markers: ✅ = verified by reading the code · · = traced by hunter, high confidence.

---

## Carry-over from #3 (partial fix shipped)

`#3` fixed gossip-duplicate / self-admission commits (dedup by commit bytes). **Not** fixed: a commit arriving *before* its predecessor (gossip reorder) still errors in `process_commit` and is dropped → that joiner stays an epoch behind permanently. Needs a reorder-resync path: buffer out-of-order commits + a state-request / commit-retransmit when a gap is detected. `private_group_runtime.rs` `process_commit_once` (see `ponytail:` note there).

---

## HIGH

### ~~7.~~ FIXED — Global message queue shared by 4 runtimes, non-atomic — `moss_ffi.rs` `drain_messages_where`
One process-global `RECEIVED_MESSAGES`; DM/group/channel/org each take-whole-queue → release lock → filter → re-append remainder, behind separate runtime mutexes. Take and re-append are two critical sections, so a second drain in between sends the first one's leftovers back behind newer frames: same-kind frames are read out of order, and an MLS Commit read before its predecessor is dropped. Since 0.7.4 one node carries every conversation, so the drains overlap by routine rather than by luck. Unclaimed frames were also kept and re-appended by every reader forever.

Fixed: per-owner queues (`inbox.rs`, ADR 0020). A kind registers what it recognises once and gets an `Inbox`; the moss callback files each frame under its owner; a drain takes only its own — no filter, no leftovers, no shared state. The claim stays a closure the kind supplies, so channel naming stays with the kind (ADR 0019). `drain_messages_where` is gone; `drain_received_messages` is now `inbox::drain_all` (every queue plus the bounded unclaimed tail) and stays the test reset. Unit-tested in `inbox.rs`; group and channel inbound verified end-to-end with `mosh-probe`.

### ~~25.~~ FIXED — Message lost when the DM leaves the relay — `private_dm_runtime.rs` `drain_relay_results` + `private_dm_runtime/relay.rs`
A send made while the session is `Relayed` is handed to the relay worker and left `Pending`. If the session then migrates `Relayed -> Direct`, `release_relay` drops the last ref, the worker's intake disconnects and it fails every queued job. `drain_relay_results` settles a still-`Pending` attempt as `Failed`. `pump_unacked_resends` only re-sends attempts whose status is `Sent`, so nothing ever retries it: the message is gone until the user presses retry by hand, on a conversation that now looks connected.

Found by `scripts/probe-e2e.mjs` against a real peer, 2026-08-21. Reproduced on `main` as well as on the 05d branch (main 1/3 delivered, 05d 2/3 over one alternating series against the same counterpart), so it is not from the conversation-seam work. Every send in the series happened while the path was still `relayed`; the losing runs are the ones where the migration to `direct` landed before the worker drained.
Fixed: `RelayJobResult` now carries `retryable`, set only where the worker fails jobs because its intake disconnected (the relay was released). `drain_relay_results` re-opens such an attempt and re-routes it through `route_prepared` on the session's current path instead of settling it `Failed`, so it ends up `Sent` or honestly failed — never in a state nothing re-drives. Regression test: `a_send_the_relay_never_tried_is_rerouted_not_failed` (fails with `Some(Failed)` on the old code).

Ceiling: a relay released again while the re-routed job is queued simply reports retryable once more. The path hysteresis (`T_DIRECT_STABLE_MS` / `T_DIRECT_LOST_MS`) bounds how often that can happen, so there is no counter on the re-routes.

### 8. · send stuck "Pending" on crash — `private_dm_runtime.rs:529, 583`
Attempt persisted as `Pending` → published → marked `Sent` in memory → `persist_outbound_state(.., false)` clears it at :583. Crash between publish-success and :583 → on-disk attempt stays `Pending`, rehydrates as a stuck "sending" message; user resends → peer dup (peer dedups on message_id, but the stuck-sending UX remains).
Fix: persist the Sent/cleared state in the same write that records the publish outcome.

---

## ~~#14~~ FALSE POSITIVE — jitter-buffer force-skip

Claimed force-skip could emit out of order / move the cursor backwards. TDD'd it (`jitter-buffer.test.ts` "emits strictly increasing seqs across a forced skip"): the test passed on unmodified code. The invariant *all pending keys > cursor* holds — `push` rejects `seq <= cursor`, and the cursor only ever advances to a pending key (which is therefore > cursor), so the force-skip min is always > cursor. No bug; regression test kept.

## MEDIUM

### 18. · Admin-leave handoff lost — `private_group_runtime.rs:1055-1075`
Admin `close` publishes a self-remove Commit + `AdminHandoff` one-shot (publish even treats `NoPeers` as success), then removes itself. If either frame is dropped by gossip, members keep `current_admin_fingerprint` pointing at the departed admin → group permanently frozen for joins/removals (all admin-gated).
Fix: gate admin departure on confirmed delivery, or let members detect a dead admin and elect the deterministic successor locally.

### ~~21.~~ FIXED — Snapshot auto-switch races user switch — `use-private-dm-snapshots.ts`
`nextActiveTarget` ran every 1 s poll and force-selected `sessions[0]` when the current target wasn't found. An in-flight poll returning before a just-created session appeared reset `active` away from the chat the user just opened.
Fix: `nextActiveTarget` now takes a `seen` set (every id ever observed in a snapshot, maintained by `seenRef`). A non-null `current` that was never seen is kept (freshly created, poll hasn't caught up); it only auto-switches away once the target was seen and is now gone (real delete), or when `current` is null. Unit-tested (`use-private-dm-snapshots.test.ts`).

### ~~24.~~ FIXED — Follow-up timer after unmount + ref-write during render — `use-private-dm-snapshots.ts`
`window.setTimeout(() => void followUp(true), 0)` in `finally` had no cleanup → a coalesced follow-up poll ran on an unmounted hook. `refreshRef.current = refresh` was assigned during render (StrictMode/concurrent hazard).
Fix: store the timeout id in `followUpTimer` and clear it in the effect cleanup; assign `refreshRef` inside the effect instead of during render. Unit-tested (`use-private-dm-snapshots.test.ts` "does not fire a coalesced follow-up poll after unmount").

---

## LOW

- **`moss_ffi.rs:520`** — `publish` treats `MOSS_ERR_NO_PEERS` (-6) as success → data message shown `Sent` but dropped before mesh forms. Surface NoPeers as soft-fail, keep retryable.
- **`voice/VoiceMessage.tsx:74-79`** — `peaksFromBase64` recomputed every render → redundant canvas redraws. `useMemo` on `peaks_b64`.
