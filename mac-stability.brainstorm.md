# mac-stability — brainstorm

Source: the 0.9.4 macOS stability report (2026-09-24), checked against the
code at `d01d0b7` (same runtime code as the `v0.9.4` tag), plus two new field
reports: macOS asks for the login password twice on every launch, and voice
breaks up in calls (macOS all call long; Windows the first ~15 s).

## Problems confirmed in the code

| # | Problem | Where |
|---|---------|-------|
| P1 | Connected comes from any decrypted frame, Offline from "no row in `peer_details` for 5 s". Gossip frames arrive without that row, so the state flips back and forth. A failed `mesh_info()` also reads as "gone". | `session.rs` `pump_reachability`, `transport.rs` `reach` |
| P2 | The outbox waits for `reach() != None` even though a room publish does not need that row. Text sits queued while the chat can work. | `session.rs` `can_deliver` |
| P3 | Each served chunk calls `OpenStream`. For a peer moss does not know, that runs `ResolveRoute` (20 s). For a relayed peer, `RelaySendTo` waits up to 5 s. Up to 64 chunks per request, all under the one DM mutex. No backoff after a failed stream. | `blob.rs` `route_blob_frame`, moss `node_types.go:709` |
| P4 | The DM protocol only moves when the UI polls. The Dart tick waits for all three list kinds, so one slow kind holds the others. | `auto_poll_provider.dart`, `private_dm_runtime.rs` `drain_inbound` |
| P5 | "handshake landed; session connected" is logged on every frame, not on the change. "dropping unverifiable hello" hides why. | `session.rs`, `control.rs` |
| K1 | The macOS DMG is signed ad hoc. The data-protection keychain needs `keychain-access-groups`, which ad-hoc signing cannot carry (`-34018`), so the 0.9.1 fix always falls back to the login keychain. The ad-hoc identity is the binary hash, so "Always Allow" does not hold. | `secure_storage.rs`, `scripts/macos-package.sh` |
| V1 | Every 20 ms the call drain takes the DM mutex and runs a full `drain_inbound` + `tick` (mesh_info JSON, hello, outbox, resends, persistence). Sending a frame takes the same mutex. Any long hold (P3) stops the audio. | `api/private_dm.rs` `call_*_frames` |
| V2 | Playback starts with no playout delay: the device callback reads the ring as soon as the first frame lands, and any late frame is silence. A full ring throws away the whole backlog. | `voice_call_playback.rs` |

## Options and choices

### K1 — signing

- A. Apple Developer ID. The real fix, but $99/year and the user said no for now.
- B. **Self-signed code-signing certificate (chosen).** Free. The designated
  requirement becomes "this identifier + this certificate", which stays the
  same across builds, so the login-keychain "Always Allow" sticks. Gatekeeper
  still warns, same as today. The certificate and key live in two GitHub
  secrets. Without the secrets (forks, local builds) the script keeps the
  ad-hoc signature.
- C. Store the DEK in a file. No prompt at all, but gives up at-rest
  protection. Rejected.

Risk: this cannot be proven on the Windows host. It needs one CI run to show
the signature, and one real Mac run (update over update) to show the prompt
is gone.

### V1 — call media off the DM mutex

- A. **A `CallMedia` hub next to the runtime (chosen).** It holds the active
  calls (call id, room, own direction) and the transport. Send goes straight
  to `transport.publish`. Drain reads a separate media inbox. Neither touches
  the DM mutex. The runtime syncs the hub from its call state after every
  tick and every call action, so the state machine stays the one owner of
  "which call is active". The API layer caches an `Arc<CallMedia>`, so the
  20 ms loop never locks the runtime.
- B. Keep frames in `CallState` but use a finer lock. Still couples audio to
  the runtime lifetime and the tick. Rejected.

Media frames get their own inbox claim (`voice-call/…`), so the DM drain no
longer sees them. `DmTransport` gets `drain_media()`. The memory test net files
call-channel frames into a separate queue.

### V1b — SendStream for voice?

Checked and **skipped**. When moss has a direct row for the peer, gossip
already hands the frame straight to that peer (it is a known subscriber), so a
stream saves almost nothing. When the peer is relayed or unknown, the stream
path blocks (`RelaySendTo` 5 s, `ResolveRoute` 20 s): much worse for a 20 ms
frame. The "first 15 s" symptom points at moss topic discovery
(`overlayTopicDiscoveryEvery = 15 s`) for the brand-new per-call topic. That
is a guess until measured. Next step after this work: log moss
"no subscribers and no mesh peers" drops during a call. If confirmed, the fix
is a warm topic (a per-session voice channel), which is a wire change and a
separate task.

### V2 — playout buffer

**Prime the ring (chosen).** The renderer plays silence until 60 ms (3 frames)
are buffered, then plays. On an underrun it re-primes. The ring grows to
320 ms. When the backlog goes past 200 ms, drop the oldest samples down to the
prime level instead of clearing everything. This is the simplest form of what
NetEq does. `ponytail:` fixed 60 ms target; make it adaptive if field logs
show steady underruns.

### P3 — blob route

Choose the stream only when `reach()` is Direct, read once per request.
Relayed and unknown peers go straight to the room wire. After a stream
failure, keep the session on the room wire for 10 s. Fix the wrong comment in
`transport.rs`. Moving all blob I/O out of the mutex is a bigger redesign and
is out of scope. With the two long waits gone, a chunk no longer blocks for
seconds.

### P1 + P2 — reachability model

- A. Make the window longer. The report warns against it: it only hides the
  symptom. Rejected.
- B. **Freshness of authenticated contact (chosen).** While Connected, send a
  Hello keepalive every 10 s. The peer already answers any Hello outside its
  own 2 s cadence, and old clients do too. Connected drops to Handshaking only
  after 25 s with no authenticated frame. `reach()` stays for the transport
  label and the blob route. It no longer decides Connected. A failed
  `mesh_info()` changes nothing. The outbox needs only the MLS side
  (`can_encrypt_for_peer`). A refused publish (`NoPeers`) already keeps the
  text queued, and resend + ack cover loss. That is the contract the report
  asks for: route, queue and ack agree.

Cost: one small MLS frame per 10 s per connected session in each direction.
Detecting a real loss now takes 25 s, not 5 s.

### P4 — protocol driven by the UI

- **Rust service thread (chosen):** one thread started with the DM runtime.
  Every 500 ms it locks the runtime and runs `drain_inbound`. The UI poll
  still reads, but the protocol no longer depends on it.
- Dart: each kind's list refresh gets its own in-flight guard, so a slow kind
  never holds the others.
- Groups and channels keep their current poll-driven drain (the report is
  about DMs). This is noted as a follow-up.

### P5 — logs

Log "session connected" only on the change into Connected. Include the MLS
error text in "dropping unverifiable hello" (openmls errors carry no key
material).

## Out of scope

- A real Developer ID and notarization.
- A voice wire change (per-session voice topic).
- Moving all blob I/O off the mutex.
- A background worker for groups and channels.
- macOS App Nap control (`NSProcessInfo` activity) during calls.
