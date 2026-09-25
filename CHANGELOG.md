# Changelog

All notable changes to Mosh are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.6] - 2026-09-25

From the 0.9.5 report on two Macs.

### Fixed
- **macOS stops asking for the password on every update.** The history
  key now lives in a file in the app's own container, not the login
  keychain. Without an Apple Team ID the keychain ties an item to one
  exact build, so every update asked again, twice, and the self-signed
  signature in 0.9.5 could not change that. Existing installs move the
  key over once: one last prompt, then none.
- **Chats no longer vanish when the network port is taken.** A dead
  earlier Mosh still held UDP 8765, moss could not start, every saved
  chat was hidden and new chats failed with "could not reach the
  network". The node now starts on a free port instead.
- **Voice notes and files arrive in seconds between Macs.** macOS will
  not send a UDP datagram over 9216 bytes by default, and each 32 KB
  chunk went out as one ~59 KB datagram, so a 5 s voice note took about
  a minute of re-requests. Chunks are now 4 KB, and moss raises its send
  buffer so larger frames leave a Mac too.
- **Settings no longer crashes on some audio drivers.** A virtual driver
  (Apowersoft) reports its sample rates as 0 to DBL_MAX; turning that into
  an integer killed the app whenever Settings listed the microphones.
  `record_macos` is vendored with the fix.

## [0.9.5] - 2026-09-25

The stability round, from the 0.9.4 macOS report: a status that flipped
every few seconds, texts stuck in a working chat, calls that broke up,
and a keychain password asked on every launch.

### Fixed
- **Connected no longer flips to Offline and back.** A DM was judged by
  whether moss listed the contact in its peer table, but gossip carries a
  chat through other peers without that row. Connected now means an
  MLS-authenticated frame arrived in the last 25 s; a quiet chat sends a
  Hello keepalive every 10 s. The header says "Connected · through the
  mesh" when moss lists no direct or relayed path.
- **Texts go out whenever the chat works.** The outbox waited for the same
  peer-table row. It now only needs the MLS handshake; a publish nobody
  takes stays queued, and resend + delivery ack cover loss.
- **A file transfer no longer freezes every chat.** Each served chunk
  opened a moss stream, which for a relayed or unknown peer blocked for up
  to 5 s or 20 s while the DM runtime was locked. Chunks now stream only to
  a directly connected peer, and a failed stream is left alone for 10 s.
- **Calls break up less.** Voice frames no longer go through the DM
  runtime's lock or run its full protocol step 50 times a second; they
  have their own queue. Playback buffers 60 ms before playing and after an
  underrun, and a lost frame no longer stalls playback for 180 ms.
- **The DM protocol runs without the UI.** A service thread drives
  handshakes, keepalives and re-sends every 500 ms, and one busy list no
  longer freezes the others.
- **The field log tells the truth.** "session connected" is written once
  per real change, not on every frame, and a dropped Hello names its MLS
  error.

### Changed
- **The macOS DMG carries a self-signed Mosh signature.** macOS now names
  the app the same way in every build, so the keychain can keep "Always
  Allow" for the history key instead of asking again. Gatekeeper still
  warns on first launch; see `CODE_SIGNING.md`.

## [0.9.4] - 2026-09-23

The voice round: a macOS voice message that failed to send, a macOS
callee nobody could hear, and every setting behind one gear.

### Fixed
- **macOS voice messages send again.** Recording "succeeded" but the send
  died with `PathNotFoundException` (errno 2, "No such file or
  directory"): the clip path pointed into the platform cache dir that
  path_provider maps to `NSCachesDirectory` + the bundle id on macOS — a
  directory nothing created — and `record_macos`' `AVCaptureFileOutput`
  neither creates parent dirs nor surfaces the write failure, so `stop()`
  returned a path to a file that was never written. The clip now lands in
  an explicit `mosh-voice/` subdirectory of the app cache, created
  recursively at capture start — a broken directory fails visibly at the
  mic tap, never again at send time. (Windows/iOS/Android were unaffected.)
- **A macOS callee is audible in calls.** The macOS user heard the caller,
  but the caller heard silence from the Mac. The call capture asked
  `record` for `echoCancel/autoGain/noiseSuppress`, which on macOS enables
  Apple's VoiceProcessingIO on an input-only `AVAudioEngine` graph — a
  duplex unit that, wired one-sided, is a documented silent-tap failure
  mode (the tap delivers zero-filled buffers on some devices/routes). Call capture now
  runs raw on macOS (the three DSP knobs off; Opus DTX already covers
  silence on the wire) and keeps the voice-processing DSP on the other
  platforms.

### Added
- **A Discord-like settings screen behind a gear at the bottom of the
  sessions rail.** Three sections: **Voice & Video** — a microphone picker
  (enumerated through `record`'s `listInputDevices`) and a speaker picker
  (a new mosh-core `list_output_devices` over cpal), plus a "Play test
  sound" button that rings the call tone on the picked speaker; **Connection**
  — the advanced connection controls (static peer, listen port,
  bind-interface, read receipts) moved out of the onboarding menu; **About**
  — version + crypto notice. Device picks persist in `audio-devices.json`
  in the data dir and apply at the next recording/call: capture and the
  voice composer read the input pick, call playback and the ringtone
  resolve the output pick inside mosh-core (an unknown or unplugged device
  degrades to the system default with a log line, never a failed call).

## [0.9.3] - 2026-09-23

The crash-fix release: opening a chat no longer kills the macOS app, and
the microphone permission asks at the moment of intent instead of at
chat open.

### Fixed
- **macOS chat-open crash (TCC).** Opening any conversation crashed the app
  on macOS with SIGABRT in the TCC namespace: the voice composer probed
  the microphone at mount, and with no `NSMicrophoneUsageDescription` in
  the macOS plist the system killed the process before a dialog could
  appear. The usage key is added for macOS and iOS, the sandboxed app
  carries the `com.apple.security.device.audio-input` entitlement, and
  Android declares `RECORD_AUDIO`.
- **Microphone permission now asks at the moment of intent.** The system
  dialog fires on the mic tap, not on chat open, and a refusal surfaces a
  localized snackbar through the composer's existing error path. The mic
  button always renders, so a user who declined can still reach the
  request later (and the same flow covers voice calls, whose capture
  probes the permission itself on start).

## [0.9.2] - 2026-09-22

The simplification drive: ~11,000 net lines removed with zero behavior
change (all 838 Dart tests and 366 Rust tests green throughout).

### Changed
- **Port archaeology comments stripped.** The Flutter fork kept narrating
  its dead React/Tauri predecessor in comments ("React did X -> Flutter
  does Y" mapping tables, CSS variable tokens, aria mapping notes). All
  of it is gone from `lib/`, `test/` and `mosh-core/src`; load-bearing
  notes (paired timeouts, wire-format reasoning, ADR references) stay in
  plain language.
- **Typing and read events unified.** The DM and group runtimes each
  carried their own copy of the typing cadence, expiry window and
  event-ring pushes. One shared module (`conversation::typing`,
  `conversation::read_events`) now owns them for both kinds.
- **Runtime god files split.** `private_dm_runtime.rs` (4,374 lines),
  `private_group_runtime.rs` (4,019) and `channel_runtime.rs` (1,407)
  are each now a thin facade root plus focused modules split by channel
  and concern, every module under the repo's 400-line file budget.
  Pure moves; no wire, logic, or error-text change; zero bridge drift.
- **One conversation app bar.** The three conversation kinds repeated the
  same AppBar skeleton (rail-back leading, mobile search toggle, kebab
  menu, peer-status, leave); one shared `ConversationAppBar` carries it,
  and each kind passes its specifics. Action order, tooltips and
  semantics trees are byte-identical.
- **Oversized widgets split.** `media_viewer` (709→393 + stages part
  file), `attachment_card` (468→321 + branches part file),
  `onboard_menu` (362→241 + part file).
- **Test scaffolding consolidated.** Thirteen test files carried private
  copies of the same message/snapshot builders; one shared
  `test/support/message_builders.dart` owns them now.

### Removed
- Dead `PrivateGroupRuntime::new` constructor (nothing called it).
- Dead Rust voice-call modules: `voice_call_drain` (196 lines, never
  wired), `voice_call_frame_crypto` + `voice_call_jitter` (463 lines —
  the Dart twins in `lib/src/features/voice_call/` are the live path
  and carry their own tests).
- `docs/superpowers/` — the port-era process archive (10,495 lines):
  task plans for the deleted React/Tauri app. Superseded by the ADRs;
  nothing references the directory.

### Fixed
Review findings (16, each with a regression test):
- **Shared-node leaks on join/create failure.** A `public_key_hex`
  failure after the room opened returned without closing it, pinning
  the shared node forever; the room now closes on the error path
  (channel join, group create, group join key + KeyPackage paths).
- **One malformed channel frame poisoned a whole drain.** A bad frame
  aborted `drain_inbound` and discarded every valid frame behind it;
  bad frames now drop with a warn log, like the DM and group runtimes.
- **A failed control frame could never repair itself.** The group
  replay set recorded control frames before verification, so a
  retransmission of anything that failed was swallowed as a replay;
  the control channel is now exempt (every handler branch is
  idempotent), mirroring the DM runtime's rule.
- **Read receipts lost on publish failure.** The DM runtime filed a
  receipt as sent even when the transport rejected it, so the peer
  never learned the message was read; the id and self-read event now
  record only when the transport took the frame.
- **Roster-lag horizon overflow.** `own + ROSTER_LAG_HORIZON`
  overflowed near `u64::MAX` (debug panic, release wrap admitting
  out-of-horizon roster claims); checked arithmetic now drops
  everything when the horizon itself overflows.
- **Call state dead-ends.** `call_start` stranded its slot on
  subscribe/offer failure (dead call until the 45s timeout, no new
  calls); `call_accept` left the phase Active when the accept publish
  failed (retry rejected as "no longer ringing"); `call_decline`
  cleared before publishing (failed decline left the peer ringing with
  no local retry); a `handle_call_offer` subscribe failure left a
  stored ring nobody could deliver into. All four paths now roll back
  so the next attempt lands cleanly.
- **Malformed attachment thumbnails crashed the conversation.**
  `base64Decode` threw during build, escaping `Image.memory`'s
  errorBuilder; the decode now falls through to the broken-image
  fallback.
- **Conversation header slot mismatched the drawn toolbar.** The kind
  headers reported `kToolbarHeight` (56) while drawing 54/70px; the
  Scaffold clamped its slot to the reported height, clipping the
  desktop toolbar and leaving a gap on mobile. A wrapper re-reports
  the height the AppBar actually draws.
- **Play-during-download never played.** A play tapped while a voice
  message was still downloading only queued the file load; the card
  now queues the play itself.
- **Pull-to-refresh left the rail stale.** It only re-read the DM list
  while the rail renders all kinds plus orgs; it now refreshes every
  slice.
- **Media viewer async failures surfaced as unhandled errors.** The
  unawaited `player.open` rejection escaped the constructor's try
  block; opens are now awaited inside the stage with a fallback card.
- **Recorder teardown races.** Manual stop, the auto-stop timer and
  discard could overlap the recorder teardown; a single-flight guard
  makes them mutually exclusive.

## [0.9.1] - 2026-09-21

The macOS-first maintenance release. Mac users get the universal DMG
channel and three frictions gone: no more login-keychain password
prompts to reach the history DEK, no more chats silently vanishing
after a restart behind `missing MLS snapshot`, and Rust panics now
leave a line in the field log so a crash report has evidence to attach.
Everyone gets the fingerprint lock that replaces the dead confirm pill
and a pass of UI polish.

### Added
- **Rust panics mirror into the field log.** A panic hook installed from the
  first Rust entry point writes an `error panic <location>: <payload>` line
  (new `panic` kind) before the default hook runs, so a release build that
  dies on a foreign thread (a Go callback, an audio worker) leaves evidence
  in `mosh.log` instead of going silent.
- **Telegram-style fingerprint lock in the DM and group headers.** A small
  lock next to the peer name (DM) or group label (group) opens one shared
  dialog: the 4-emoji fingerprint derived from Telegram Desktop's own
  333-emoji pool (`fingerprint_emoji.dart`, pool extracted from
  `calls_emoji_fingerprint.cpp` by script), the hex string, and a
  compare-out-of-band hint. Both sides of a chat read the same
  fingerprint (the creator's / `creator_fingerprint`), so the emoji match
  when nobody swapped the invite. Groups get a "compare with the creator"
  hint; channels stay unchanged.

### Changed
- **macOS release channel: a universal (Apple Silicon + Intel) DMG.** One
  `build-macos.yml` workflow builds it — reusable, same artifact for the
  main-push proof and the tagged release, plus `workflow_dispatch` for the
  v0.9.0 retro-attach. The Go library now builds universal on darwin (one
  slice per `GOARCH`, stapled with `lipo`); the Xcode project gains a
  "Moss Runtime" copy phase so `libmoss.dylib` lands inside `mosh.app`
  (`Contents/MacOS/`, where the loader probes); the release entitlements
  finally allow network (client + server) and user-selected files, which
  the sandboxed release build needs to work at all. CI gains a macOS
  clippy+test lane and a DMG packaging proof. The supported floor is macOS
  12 Monterey (the Go 1.25 runtime's minimum). The DMG is unsigned:
  Apple's documented first-launch flow — try to open, then System
  Settings → Privacy & Security → **Open Anyway** — is in README.
- **macOS universal libopus.a provisioning** (`scripts/opus-prepare-macos.sh`).
  audiopus_sys's vendored opus cannot cross-compile (no `--host` in its
  configure), so the x86_64 slice of the universal app had nothing to
  link; the script builds one slice per arch from the crate's own vendored
  source, lipos them, and the podspec points `LIBOPUS_LIB_DIR` at the
  result — the same shape the Android lane uses with the NDK. CI caches
  the artifact.
- **Code signing policy updated: Mosh ships unsigned everywhere.** The
  SignPath Foundation application was declined, so the Windows artifacts
  stay unsigned too; `CODE_SIGNING.md` now documents what a user sees on
  both platforms and what would change if a certificate ever exists.

### Removed
- **The fingerprint confirm flow.** The header confirm pill, the dead
  `FingerprintConfirmScreen`, the screen's in-memory confirmed set, the
  kebab "Confirm fingerprint" item, and the confirmed/unverified subtitle
  variants are gone: a local confirm flag gates nothing and dies on
  restart, so the surface is now read-only (the lock + dialog above).
  The DM header subtitle is the plain connection status sentence.

### Fixed
- **macOS no longer prompts for the login password to reach the history
  DEK.** Sandboxed macOS builds (dev runs and the DMG both enable the app
  sandbox) now use the data-protection keychain instead of the legacy
  login-keychain store, whose ACL flow can show the "app wants to access
  your keychain" prompt at every launch for an ad-hoc-signed build — and the
  legacy-slot migration fallback could fire a second prompt in one launch.
  The protected store is probed with a real set/get/delete roundtrip before
  it is trusted, and the two legacy login-keychain slots are handed over
  once (one possible last prompt), after which the prompt is gone.
- **Chats no longer vanish after a restart with `missing MLS snapshot`.**
  A DM record whose MLS snapshot write failed silently, or a joiner
  placeholder written before its Welcome, used to stay on disk forever while
  rehydrate skipped it with the same warning. Now: `accept_invite` writes no
  record until the Welcome lands (record + snapshot go down together);
  rehydrate deletes joiner placeholder rows (empty group id) instead of
  warning at every startup; a final record missing its snapshot is kept —
  its history rows stay recoverable — and reported distinctly; and a failed
  snapshot write is logged (`persist` kind) instead of swallowed.
- **DM/group rehydrate distinguishes a missing snapshot row from an
  unreadable one.** `Ok(None)` vs `Err` from the snapshot read now produce
  different log lines, so a DEK mismatch no longer masquerades as a
  `missing MLS snapshot`.

## [0.9.0] - 2026-09-21

The messenger release on the census core: presence you can see (typing
indicators), a network you can diagnose (the honest channel probe, the
field diagnostics panel), attachments that ride the mesh's own streams
with a byte-identical fallback for older counterparts — all validated
against and shipping with moss v0.9.0, the fleet-census batch that
closed the ghost-punch, NAT-blind coordination and interface-selection
defects.

### Added
- **The diagnostics panel shows which moss library is actually running**
  (spec #5). The "Moss network" group of the peer-status drawer gains the
  Library version row (the loaded library's own answer through the same
  dynamic-symbol table as every other moss call; a copy older than
  v0.8.17 answers "unknown" instead of failing the node), the Peer RTT
  row (the last measured round-trip time to the active DM counterpart,
  "unknown" when moss has no measurement — never a fabricated "0 ms";
  DM drawers only, since a channel and a group have no single
  counterpart), and the Field log row (the file ticket #4's sink
  currently writes, so a bug report can be pointed at it). The first
  read in a process also files the version into the field log, so the
  attached report carries what was running. The api function is
  `moss_library_info(peer_moss_id)` — additive; `MossLibraryInfo` is
  constructible from Dart; the frb-generated mirrors for it are regenerated
  and committed (9df8ace).
- **Attachment chunks ride moss streams on direct DM sessions** (spec #8).
  The blob channel keeps its chunk protocol — requests, retry, dedup are
  byte-for-byte unchanged — and only the carrier changes: when the
  counterpart's moss id is known, a served chunk goes down attachment stream
  id 2 (`Moss_OpenStream`/`Moss_SendStream`; moss wraps relayed peers with
  its 8-byte `MSs1` header itself). Any stream refusal (missing symbol,
  `RELAY_FAILED`, node gone) falls back to the room wire, so a counterpart
  library without streams receives exactly as before; the receiver keeps its
  room subscription, and the carrier's framing (a JSON header naming the
  destination blob channel around the original envelope, carried on the
  reserved `moss-stream/<peer>` inbox channel) is only ever read by peers
  running this code. Groups and channels keep the room wire — a direct
  single-peer stream does not exist for them. The receive-side stream
  handler registers once per shared node at start (best-effort). `Moss_Version`,
  `Moss_PeerRTT`, `Moss_OpenStream`, `Moss_SendStream` and `Moss_OnStream`
  are loaded as optional symbols that degrade instead of failing the load.

### Changed
- **The channel probe sends the message itself as the rendezvous probe**
  (`channel-dial`). It used to wait for "any substrate peer" before sending —
  but substrate peers are strangers, not channel members, so a channel whose
  real rendezvous needed more time reported a false failure. The probe now
  sends straight away and, when moss answers "no peers yet" (the frame never
  left the device), re-drives the same message on every tick until the send
  is accepted or the timeout is spent. Every retry lands in the timeline with
  its attempt number and elapsed time, making channel rendezvous latency
  measurable for the first time. The verdict stays with the listening end;
  the runtime's refusal of a peerless publish is unchanged (ADR 0021) — the
  probe retries around it. `--send-without-peers` keeps its meaning: one
  attempt, watch the refusal.
- **Moss bumped to v0.9.0** (from v0.8.19; the pin is the `moss/`
  submodule pointer — ADR 0002). Upstream highlights across the delta:
  directed delivery no longer lets one slow peer drop another peer's DMs
  (the exact shape of Mosh's synchronous FFI callback), relay
  rate-limiting made visible instead of silent, ping probes dispersed so
  one stalled write can no longer serial-kill healthy sessions, bounded
  fan-out for stat gossip, and the conditional UDP-handshake reap. v0.9.0
  itself is the fleet-census batch: bidirectional UDP confirmation
  before a datagram session registers, NAT profiles riding signed punch
  coordination envelopes, instantly refused dials charged to the dial
  budget, static peers given a bounded dual-transport dial, the
  overlay-lookup and restart-listener data races closed under the race
  detector, advertise led by the default route's egress address (a
  public box no longer hands its docker bridge to the fleet) with
  docker/CNI bridges excluded and own-endpoint observations no longer
  minting `port_restricted_cone` verdicts, and moss-lan breaking
  self-address collisions by peer-ID rank. The FFI surface Mosh uses is
  unchanged — all 28 symbols from v0.8.19 keep their signatures; the 8
  newer symbols (directed sends, streams, packet callback,
  `Moss_Version`) are additive and remain unused for now.
- **A Mosh client no longer ships Axiom telemetry.** The node config
  hardcoded moss's own ingest token, silently opting every user into
  error reporting; moss's sink is opt-in, and the default config now
  carries no `axiom_*` keys. A test pins this.

### Added
- **Typing indicators for DMs and private groups.** While you type, the
  composer signals the counterpart (or the group) over the MLS-encrypted
  control wire: a `TypingIndicator` frame whose body never crosses the mesh
  in the clear, so a bystander cannot forge "someone is typing". Continued
  input refreshes at most every 3 s; the receiving side owns a 5 s expiry and
  clears the hint the moment a real message arrives — a delivered message
  contradicts "typing". A group hint identifies WHICH member types
  (fingerprint + display name in the snapshot); channels never carry typing.
  Mixed-version tolerance rides the established unknown-envelope decode-drop:
  an old client never shows typing and nothing breaks. The runtime files a
  `typing` event (pinned code 10) into the diagnostics event ring, and the
  snapshots (`SessionSnapshot.peer_typing_until_ms`,
  `GroupSnapshot.typing_members`) carry the state to the UI through the
  existing poll cycle — no new push channel.
- **Read receipts for DMs: the two delivery ticks change color.** When a DM
  is open on screen, the runtime receipts every not-yet-read counterpart
  message with a `ReadReceipt` frame on the MLS-encrypted control wire —
  one message id per frame (the ack shape), so only the real MLS peer can
  mint one and a mesh bystander cannot fake the color change. Off by
  default and symmetric: one app-level toggle covers every DM, persisted
  both ways (`read-receipts.json` beside the history store) — and a user
  who does not send receipts does not see others'. Read state survives a
  restart (ids ride the session record, capped at 512), so the counterpart
  is never re-asked. The runtime files a `message_read` event (pinned code
  9) into the diagnostics event ring on BOTH sides — when a receipt lands
  and when one is sent — and the snapshot's `ChatMessage.read` (own
  messages only, skip-when-none) carries the color to the UI through the
  existing poll. DM only: groups ("read by N") and channels are out of
  scope. Old counterpart clients decode-drop the unknown frame and
  silently never color.
- **A field log the app can hand to support.** The Rust core's error lines
  (dropped frames, failed handshakes, stalled resends, rehydrate failures)
  used to go to process stderr, which a release Windows build has no console
  for — every line was silently lost. They now land in one rotated plain
  file under the app-private data directory (`<data dir>/mosh/logs/mosh.log`),
  written by a single sink that owns the path and the rotation policy
  (~2 MB per file, `mosh.log` → `mosh.log.1` → `mosh.log.2`, oldest dropped).
  Lines are structured and greppable — `timestamp level kind context message`
  — and the log never breaks the app: a filesystem failure drops the line
  and the next write retries. Debug builds still mirror every line to stderr.
  Key session transitions join the errors: handshake landed, resend attempts,
  delivery settlement. The location is surfaced through
  `current_log_path()` so a support conversation can end with "attach this
  file".
- The diagnostics event log names the messenger events moss added in
  v0.8.20 (`message_delivered`, `message_read`, `typing`, `presence`)
  instead of rendering them as `unknown`. Mosh does not act on them yet.

### Removed
- **The dead moss release-pin flow**: `moss.config.json` (stuck on v0.8.14
  while the submodule sat on v0.8.19) and `scripts/moss-update.mjs` (its
  config helpers lived in the removed React app). The submodule pointer is
  the one canonical pin; CI already keys its library cache on the
  submodule sources.

## [0.8.0] - 2026-09-02

The first release of Mosh on Flutter. The desktop app was rebuilt from the
ground up: the React + Tauri shell is gone, the UI is Flutter, and everything
that must be right lives in one Rust core (`mosh-core`) behind
`flutter_rust_bridge` (ADR 0009, 0010, 0012). Windows ships as a per-user
installer. The same code base runs on Android (arm64) from CI, not yet as a
published build.

### Added
- **Voice calls.** Real microphone capture and speaker playback in the Rust
  core (Opus, cpal), AES-GCM sealed frames over the mesh, a jitter buffer, a
  ringtone, incoming-call OS notifications when the window is unfocused,
  mute, and call-log entries in the conversation.
- **Voice messages.** Record, review and send from the composer; play inline
  in the message row.
- **Attachments.** Drag-and-drop and paste-to-attach on desktop, image and
  video thumbnails, a media viewer with video and audio playback, opening
  files in the system handler, and download / cancel / retry controls.
- **Channels, groups and orgs.** Channel and group screens with their own
  diagnostics, DM offers from a channel or group member, the org roster
  section in the rail with admin add, and a revoked-org badge.
- **Onboarding.** Invite cards open the chat or group straight away; an
  accepted DM invite opens the chat; the `mosh://` scheme is registered on
  Windows and Android; the Advanced disclosure exposes the bind interface,
  listen port and static peer.
- **Diagnostics drawer.** Session, mesh and event-log sections with the
  peer's id, transport and last connect outcome.
- **Encrypted history.** Conversations and MLS state survive a restart. The
  data-encryption key sits in the OS credential store and is unlocked by
  user presence (Windows Hello on desktop, biometrics on Android) behind a
  lock screen.
- **Desktop shell.** A shared title bar with a live state pill, the sessions
  rail with unread badges and the active highlight, and the welcome pane with
  inline setup steps. Mobile gets the responsive rail-to-chat layout with its
  own header menu and search.
- **Two languages.** English and Russian throughout, ICU plurals included.

### Changed
- **One moss node per installation.** The DM runtime no longer starts a second
  "relay" node under the same peer id. Reaching a contact behind a NAT is moss's
  job: the app registers the contact as a connect target and moss picks direct,
  hole punch or its own network relay. Telemetry now shows each installation as
  one node.
- **An honest chat status.** The chat header says one of three things: waiting
  for your contact, contact is offline, or connected with the transport next to
  it (direct or relayed by the network). "Connected" appears only after the
  contact's app answered. The rail badge, title-bar pill and diagnostics card
  say the same thing; the diagnostics card shows the contact's peer id and the
  last connect outcome instead of a relay row.
- **A text never fails.** A message typed before the contact is reachable
  shows a clock, survives a restart, and goes out by itself in the order it was
  written, moving to a tick and then a double tick. Retry stays for
  attachments, which need a live path. See ADR 0026.
- **Messages read as rows, not bubbles**, with sender grouping, avatars,
  delivery ticks, the MLS badge and a locale-aware timestamp.
- **Release builds are smaller.** The Rust core is built with whole-program
  LTO and stripped symbols; the moss library drops its symbol table and
  build paths.

### Fixed
- **Calls.** Audio no longer dies one second after the call connects, a call
  shows one overlay instead of two, ring signaling survives a dropped frame,
  playback opens on any output device, and a failed audio setup is reported
  inline instead of silently.
- **Sending.** A message published with no peers is not marked sent; a send
  interrupted by a crash comes back as failed, not pending; a send the relay
  never tried is re-routed; every conversation kind has its own inbound queue.
- **Groups.** The admin is derived from the commit, not from a handoff frame.
- **Desktop.** Ctrl+V pastes again, local images open, the first send waits
  for the runtime, and Windows bind changes relaunch the app.
- **Peers.** The counterpart's moss id is persisted and may be re-announced
  after the handshake, so a restart finds the peer again.
- **Android.** The keyring panic is gone, the display cutout is respected, the
  key is injected only once the app is in the foreground, and the build links
  against the right native libraries.

### Known limitations
- The Windows installer is not code-signed yet; SmartScreen warns on first
  run. Verify the SHA-256 published with the release.
- Android is built by CI as a debug APK for arm64 and is not published.
- macOS, Linux and iOS are not shipped in this release.

## [0.7.4] - 2026-07-29

### Fixed
- **The rest of the client still ran a node per conversation.** 0.7.3 put every
  DM on one node; public channels, private groups and orgs each kept starting
  their own. Node identity is per process, so a client in three channels and two
  groups still announced one peer id from six ports — the exact pattern 0.7.3
  measured: a remote peer keeps one session per identity, closes the rest on
  arrival, and declines to dial the others because it already holds that id.

  Channels, groups and orgs now join a room on the same node the DMs use, so a
  whole client is one node and one port. Wire-compatible: a joined room is
  byte-identical to the same room on an older client, so 0.7.4 still talks to
  0.7.3 and 0.7.2.

- **Closing a channel, group or org kept its subscriptions alive.** With a node
  per conversation, dropping the node ended them. On a shared node it has to be
  said out loud — leaving now unsubscribes and leaves the room.

- **The joiner's first KeyPackage went to the wrong room.** `accept_invite`
  published it room-less, which since 0.7.3 means the shared node's own
  substrate room rather than the invite's. The handshake only recovered because
  the drain loop re-publishes it correctly until the Welcome arrives; the first
  attempt was always thrown away.

## [0.7.3] - 2026-07-29

### Fixed
- **A conversation only worked once every other conversation was closed.** Each
  open chat started its own moss node, and node identity is per device — so N
  open chats meant N nodes presenting the *same* peer id from N ports. A peer on
  the other side keeps one connection per identity: it closed the rest the
  moment they arrived, and refused to dial the others at all because it already
  had that id.

  Measured across three clients over three days: 33,715 connections, 32,330 of
  them dead inside one second (95%), running at 205 / 131 / 113 discarded
  handshakes an hour against only 6–8 peers each. One identity appeared on 27
  different ports within a single hour. Every one of those is a full
  public-key handshake, thrown away.

  All chats now share one node and stay separated by room (moss v0.8.19).
  Wire-compatible: a room joined this way is byte-identical to the same room on
  an older client, so 0.7.3 and 0.7.2 still talk.

- **A closed chat kept receiving.** `Moss_Unsubscribe` has existed in the
  library all along, but mosh never bound it — with a node per chat, dropping
  the node ended its subscriptions. On a shared node it must be said out loud.
  Closing a chat now leaves its room.

- **One chat's diagnostics listed every other chat's channels**, because the
  node they now share reports all of them. Filtered to the chat you are looking
  at. Peer lists stay whole — that is how a chat recognises its counterpart.

### Changed
- Moss bumped to **v0.8.19**, which is what lets one node hold several rooms.

## [0.7.2] - 2026-07-29

### Fixed
- **A file transfer that lost one chunk hung forever.** Users saw it stick at
  63%, 32% and 0%. The receiver *did* ask again — `next_chunk_request`
  re-requests the gaps below its cursor on every pump — but the repeat request
  is byte-identical to the one before it, and the inbound dedup keys on
  `channel + sha256(payload)`. So the sender dropped every repeat before
  `handle_blob` ever saw it and never re-served, and a re-served chunk frame
  (also byte-identical) would have died on the way back.

  This is the same trap that kept the MLS handshake silent in 0.7.1: the
  recovery mechanism is re-sending the identical bytes, and a payload-hash
  dedup makes recovery unreachable. The blob channel is now exempt like the
  control channel. Both directions are idempotent — serving a chunk just
  re-encrypts it, and ingesting one already held is a no-op.

  What keeps the repeats from becoming a flood is no longer the dedup but an
  in-flight window: a chunk asked for less than 10s ago is not asked for again,
  so the once-a-second pump stops re-requesting a batch still on the wire. The
  request cursor still advances a fresh window every pump, so throughput is
  unchanged.

### Changed
- Moss bumped to **v0.8.18**, which stops application delivery from stalling
  the read loop. That was the other half of the same failure: a transfer's
  chunks filled a shared delivery queue, the reader blocked behind it, and the
  transport's inbound buffer discarded whatever arrived next — the lost chunks
  above, and the pings a session dies six of.

## [0.7.1] - 2026-07-28

### Fixed
- **A DM whose first Welcome was lost hung on "connecting" forever.** This is
  the cause behind the "we still can'''t connect" reports, and it was never in
  the network layer.

  The handshake already had recovery for exactly this: the joiner re-sends his
  KeyPackage until he joins, and the creator caches her Welcome so she can
  re-answer each repeat rather than re-running `add_members`. None of it had
  ever executed. The inbound dedup keys on `channel + sha256(payload)`, and a
  retransmission is by definition the identical payload — so every copy after
  the first was dropped before the handshake code ever saw it, making the
  re-answer branch unreachable.

  Measured on a live pair before the fix: **85 KeyPackages published, one
  delivered, zero re-answers**. After, on the same rig: 18 re-answers and the
  message delivered. Control frames are now exempt from the dedup — every
  branch there already guards on `peer_joined`, so a repeat is a no-op or the
  intended re-answer. Data and blob frames still dedup, which is what keeps a
  resent message from doubling in the history.

  It stayed invisible because the existing handshake tests call the handler
  directly and never cross the dedup layer, so a mechanism that had never once
  worked in the field looked fully covered.

### Changed
- **Bundled moss → v0.8.16.** A UDP session closing while the read loop was
  delivering to it panicked with `send on closed channel`; moss is linked in as
  a shared library, so that took the whole app down rather than one session.
  Also brings the topic-rendezvous and mesh-grafting repairs — on a live pair,
  inbound PRUNEs went 16,933 to 0 and average routing contacts 0 to 7.78.

### Verified
- A real two-machine DM (laptop to a remote host, different networks) on this
  exact build: both ends `ready`, path `direct`, verdict **delivered**. Run
  twice, including once after the relay fleet was upgraded.

## [0.7.0] - 2026-07-27

### Fixed
- **The VPN bypass now does something.** It never could. A connection's network
  adapter is fixed when the connection starts, and saved conversations start
  before the window exists — so the button changed a setting that no running
  conversation would ever read again. It was a no-op for every existing chat,
  however many times it was pressed, and the choice was thrown away at exit.
- **The bypass no longer splits Mosh across two networks when it is on.**
  Underneath, some connections honoured the chosen adapter and others silently
  used the VPN, so Mosh advertised two different addresses and peers disagreed
  about which was real. Fixed in moss v0.8.15.

### Changed
- **Mosh asks once, at startup, when a VPN is carrying its traffic**, and names
  the adapter it would use instead. Answering yes is remembered and applied on
  every launch; answering no is not remembered, so the question returns next
  time — a wrong yes is visible and reversible, a remembered no would quietly
  strand someone whose network changed.
- **Mosh restarts when you change that answer.** There is no way around it:
  connections take their network adapter when they start, so a setting changed
  mid-session would apply to nothing until the next launch. One restart makes it
  true for every conversation instead of none.
- **The adapter picker moved to advanced connection settings**, and the warning
  banner is gone. Nobody should have to reason about `ipv4-tun` to send a
  message. The picker is still there for anyone who wants it, alongside the
  yes/no answer.
- The automatic pick now ignores adapters holding a `169.254.x` address. That
  range means no address was issued, so an unplugged network card could win the
  pick while being connected to nothing.
- **Moss core updated from v0.8.14 to v0.8.15.**

### Note
- **This has not been shown to fix a chat that would not connect.** It makes the
  feature work as designed and stop lying about its state, which is worth having
  on its own. Whether routing around a VPN is what rescues two peers who cannot
  find each other is still open: a laptop-to-server test delivered messages both
  with the bypass and without it, and that pair cannot reproduce the reported
  failure because one end is a public server with no NAT. The `no_relay_peer`
  failures seen in the field have a separate cause that this release does not
  touch.

## [0.6.9] - 2026-07-26

### Fixed
- **The app no longer dies when a relayed contact disconnects.** Moss is loaded
  inside Mosh, so a crash in it took the whole window down — and an ordinary
  disconnect could trigger one. Fixed upstream in moss v0.8.1.
- **Chats and lobbies appear promptly instead of on the fourth try.** Nodes were
  drowning each other in peer announcements — one relay took 21,808 of them in
  two minutes against 29 keepalive pings — and the keepalives that got discarded
  in the flood killed healthy connections after about 37 seconds. Median
  connection life between two updated peers went from 37s to 632s (moss v0.8.7
  through v0.8.10).
- **Conversations with only a couple of participants can find each other again.**
  On the shared network the peers around you are strangers, so a two-person room
  never formed a mesh and sends failed with "no peers". Moss now runs a discovery
  layer that resolves who else is in your room (v0.7.0, repaired in v0.7.7 and
  v0.8.2).
- **Mid-session stalls of several seconds are gone.** Two separate causes: a
  discovery lookup was running on the connection hot path (v0.7.7), and the app
  was redialling peers it already held, opening ~1.7 connections a second with
  95% dying instantly (v0.7.8).
- **Unreachable peers are no longer retried once a second forever.** Failed dials
  now back off up to five minutes; direct-message counterparts are exempt and
  still retried at the old cadence (v0.8.1).
- **Connection type is detected correctly.** No node could previously work out it
  was behind a symmetric NAT, so it kept attempting hole punches that could not
  succeed. Such pairs now take the relay first and get upgraded to direct
  afterwards (moss v0.7.1, v0.7.2).
- **The Axiom error telemetry added in 0.6.7 actually reports now.** The moss FFI
  was dropping the `axiom_*` config keys on the floor, so no Mosh client has ever
  shipped an event despite the setting being wired up. Fixed in moss v0.7.0, and
  the sink is enabled before the node starts, so a first-start bind failure is
  reported instead of dying with the node.

### Changed
- **Moss core updated from v0.6.20 to v0.8.14.** Installers grow by ~2.3 MB.
- **Room membership is announced to the discovery layer.** Every 30 seconds each
  node publishes, under an opaque hash, which rooms it is in, so sparse rooms can
  find each other. There is no switch to turn this off.

### Note
- **Mosh's in-mesh network telemetry has been on by default since 0.6.7** and no
  previous entry said so. It did not change in this release. It is separate from
  the Axiom sink above and much narrower: anonymised, noise-added aggregate
  metrics carrying no address and no stable identity, gossiped inside the mesh
  rather than sent to a third party. Opt out by adding
  `"telemetry":{"enabled":false}` to the node config in
  `src-tauri/src/adapters/moss_ffi.rs`.

## [0.6.8] - 2026-07-16

### Fixed
- **Windows client no longer crashes under sustained load.** The bundled moss
  runtime is now built with the Go 1.25.x toolchain (pinned via `GOTOOLCHAIN`
  in `scripts/moss-prepare.mjs`). Go 1.26.1's Windows runtime corrupts memory
  (`0xc0000005`) under the heavy concurrent UDP the DHT drives, crashing the
  client after a few minutes. Bisected across seven soak runs: DHT-off was
  stable, every DHT-on build on 1.26.1 crashed at 2–11 min, the race detector
  was clean (not a data race), and forcing raw sockets did not help — but the
  same build on Go 1.25 ran a full 13-minute soak with DHT enabled at 259/259
  messages and 0% loss. DHT stays fully enabled.

### Changed
- Bundled moss runtime → v0.6.20 (public `SetMessageCallback`, `dht_enabled`
  config toggle, `MOSS_FORCE_RAW_UDP` escape hatch).

## [0.6.7] - 2026-07-15

### Added
- **Opt-in error telemetry to Axiom.** moss's own failures (listen/tracker/
  handshake/relay, including the Wine/Proton bind failure) and periodic node
  stats now ship to the `moss-events` dataset, so real-world client failures are
  queryable instead of relying on the user to send logs. Ingest-only token,
  embedded like a Sentry DSN. Bundled moss → v0.6.18.

## [0.6.6] - 2026-07-15

### Fixed
- **Direct messages reach the "direct" path again on the shared network.**
  The shared-substrate rework made a DM's counterpart just one of many world
  peers, so two chat endpoints only ever connected to each other by luck and
  the conversation stayed stuck on "relayed via supernode". Each side now
  asks moss to connect to its specific counterpart (moss v0.6.15
  `ConnectToPeer`): dialed immediately, retried until connected, then
  upgraded from relayed to direct as before.
- **The connection status no longer flickers between "relayed" and "warming
  up".** Relay readiness is now held for 10 seconds across momentary
  relay-peer drops instead of tracking every blip, and the background send
  worker no longer stalls on those blips either.
- **The network no longer piles onto supernodes.** Nodes used to dial
  relay-capable supernodes first, funneling the whole network's gossip
  through the relay infrastructure. Peer selection is neutral now, keeping
  just two relay-capable connections as a fallback (moss v0.6.15).

## [0.6.0] - 2026-07-14

### Fixed
- **The app no longer freezes while a relayed chat is connecting.** Sending
  over the relay used to block the whole interface for several seconds at a
  time whenever the relay link was still warming up or the peer was
  unreachable. Relay sends now run in the background: messages queue up, wait
  for the relay to become usable, and retry on their own.
- **Messages sent while the relay is warming up no longer fail instantly.**
  Instead of an immediate "relay send failed", a queued message stays marked
  as sending and goes out as soon as the relay converges (or reports a real
  failure after retries).

### Added
- **Delivery receipts in direct messages.** Your own messages now show their
  real journey: *sending…* → *✓ sent* (left this device) → *✓✓ delivered*
  (the peer's app confirmed receipt). Until a message is confirmed, Mosh
  automatically re-sends it in the background — so a message published into a
  dead connection no longer vanishes silently while looking "sent".
- **Diagnostics show relay warm-up.** While the shared relay node has not yet
  found a relay-capable supernode, the conversation's Path row reads "relayed
  via supernode (warming up)" so a not-yet-usable relay is no longer
  indistinguishable from a working one.

## [0.5.1] - 2026-07-13

### Fixed
- **Direct messages follow a peer to their current address.** A one-to-one chat
  no longer stays pinned to the first network identity it saw for someone. When
  a contact reconnects from a new location or restarts, Mosh now tracks their
  latest address, so messages keep flowing instead of silently going to a stale
  endpoint.

## [0.5.0] - 2026-07-13

### Added
- **Organizations: join a team roster and message its members.** A company or
  group can now run Mosh as a closed network. You join an organization from an
  invite link, which shows you a short confirmation code to read out to your
  admin — no keys to copy, no way to be added by someone who doesn't already
  have your code. Once approved you see the org's member list and can start an
  end-to-end encrypted direct message with anyone on it in one click, without
  swapping invite links first.
- **Org groups.** An org admin can spin up a group chat and pull in members
  straight from the roster. The group is bound to the organization: only people
  the admin has approved can be in it.
- **Membership is enforced, not advisory.** When an admin removes someone from
  the organization, that person is automatically dropped from every org group —
  and the removal sticks across restarts and for groups you had closed at the
  time. Removed members lose access to future messages; a "no longer in" marker
  shows on any direct chat with someone who has left. If a group ever falls too
  far behind to catch up on membership changes, Mosh tells you to ask an admin
  to re-invite you rather than showing a silently stale member list.
- **The roster is cryptographically signed by the organization.** Membership is
  gossiped peer-to-peer with no central server, and every client verifies the
  organization's signature and rejects any attempt to roll the roster back to an
  older version. Messages stay end-to-end encrypted throughout (OpenMLS +
  Noise); the roster only decides who is allowed in, never what is said.

### Notes
- Creating and administering an organization is done with a separate admin tool
  that holds the organization's signing key; the Mosh app never sees that key.
  Personal one-to-one DMs and groups are unchanged and need no organization.

## [0.4.3] - 2026-07-08

### Fixed
- **A transient hole punch no longer kills the relay path for good.** The DM
  transport state machine treated `direct` as terminal: the moment a single
  direct peer appeared — which behind symmetric NAT happens for a few seconds
  per punch before the mapping dies — a relayed conversation dropped its relay
  and switched to direct, then had no way back when the punch collapsed. The
  chat stayed stuck flapping on a dead direct path with the MLS handshake
  never completing. Now a relayed conversation only migrates to direct after
  the direct link has held for 30 s, and a direct conversation falls back to
  the relay once its peer has been gone for 5 s.
- **Hard-NAT joiners can complete the handshake entirely over the relay.** The
  invite link now carries the creator's moss peer id, so the joining side can
  relay the MLS handshake through a SuperNode even when no direct window ever
  opens. Old invites still parse; they just rely on the handshake exchange to
  learn the id, as before.

## [0.4.2] - 2026-07-02

### Fixed
- **Relay fallback can actually find a relay.** Bundled Moss core bumped to
  `f3bb2fb`: a relay SuperNode now periodically re-advertises its status, so a
  client that joins the shared relay mesh *after* the relay came online learns it
  can route through it (previously the one-shot promotion notice was missed and
  relay selection found nothing). Without this, the 0.4.0 relay-fallback path was
  inert for the common case; direct-capable DMs were unaffected either way.

## [0.4.1] - 2026-07-02

### Fixed
- **NAT detection works on IPv4-only networks.** Bundled Moss core bumped to
  `adb5a96`: STUN and peer address resolution is now forced to IPv4 to match
  Moss's IPv4-only transport. Previously, on a network with no IPv6 route, a STUN
  hostname could resolve to an IPv6 address that the v4 socket can't reach, so
  NAT detection stalled at "unknown" — affecting the relay-fallback path for
  peers on IPv4-only carriers.

## [0.4.0] - 2026-07-02

### Added
- **Direct messages now reach peers behind hard NAT.** When a one-to-one chat
  can't hold a direct link — the case for a peer on carrier-grade NAT, common on
  Russian mobile ISPs — Mosh transparently falls back to relaying the
  conversation through a volunteer relay SuperNode instead of leaving the chat
  stuck on "connecting". The relay only ever forwards ciphertext: messages stay
  end-to-end encrypted (OpenMLS + Noise) and the relay operator cannot read
  them. If a direct path later becomes possible the chat silently migrates back
  to it.
- **A "Path" row in the DM diagnostics drawer** shows whether a conversation is
  `direct`, `relayed via supernode`, or still `connecting`, and notes that
  relayed traffic stays end-to-end encrypted.

### Changed
- **Bundled Moss core bumped to `c02acb4`** for the relay-by-peer-id transport
  the fallback is built on (`Moss_RelaySendTo` + relay callback).

### Notes
- The relay fallback stays **inert until at least one public relay SuperNode is
  reachable** on the shared relay mesh. Standing up that pool ships separately
  (the MossSpore project); until a spore is live, hard-NAT DMs degrade to
  "connecting" exactly as before — direct-capable chats are unaffected.

## [0.3.1] - 2026-07-01

### Fixed
- **CGNAT peers no longer flap connect/disconnect.** Bundled Moss core bumped
  to `23d53e5`, pulling two NAT reachability fixes. Previously a node behind
  carrier-grade NAT (common on Russian ISPs) labelled *itself* publicly
  reachable purely from its STUN reflexive address and broadcast that to the
  mesh; peers then hammered a direct mapping that dies and re-opens on a new
  port each attempt, producing rapid `peer_joined`/`peer_left` churn.
  Reachability now requires a real inbound probe, and genuine carrier NAT is
  detected observationally (varying mapped port → symmetric) instead of from
  address shape. Both peers must run ≥ 0.3.1 for the fix to take effect on a
  given link.

## [0.3.0] - 2026-06-30

### Changed
- **Bundled Moss core upgraded to v0.4.0 (DPI-resistant flag-day).** All
  peer-to-peer UDP traffic is now obfuscated by a keyed scramble codec so it
  is indistinguishable from random UDP — Mosh now connects on networks that
  fingerprint-block protocols like WireGuard (notably Russian DPI). Discovery
  also gained the BitTorrent mainline DHT, a persistent peer cache for warm
  reconnect, and faster tracker bootstrap.
- **Network compatibility break:** the wire format changed, so this build does
  **not** interoperate with Mosh ≤ 0.2.x or older relays. Everyone on a mesh
  must update together. Message confidentiality is unchanged (OpenMLS + Noise);
  the codec is an anti-censorship wrapper, not the encryption layer.

## [0.2.10] - 2026-06-17

### Fixed
- **Voice-call audio is encrypted with a unique nonce per frame.** A flaw in the
  call frame crypto could reuse an AES-GCM nonce across frames, which weakens
  the encryption of live call audio. Each frame now derives a unique nonce, and
  an out-of-range frame sequence is rejected instead of silently wrapping.
- **Call audio recovers cleanly after a network stall.** Playback scheduling
  could drift further and further ahead of real time once a backlog built up,
  so audio lagged for the rest of the call; it now resyncs to the present.
  Frames lost in transit no longer make the remaining speech sound stretched —
  the decoder is told where the gaps are.
- **The ringtone always stops.** An incoming-call tone could keep oscillators
  and its audio context alive after the call was answered or dismissed; it now
  stops and tears down reliably.
- **Calls are labelled missed vs. completed correctly** in the call history.
- **You're no longer pulled out of a chat you just opened.** The roster refresh
  that runs every second could yank the view back to the first conversation if
  it completed before a just-created chat appeared in the list. It now keeps the
  chat you opened until it's confirmed gone.
- **Messages sent in the same millisecond can't collide.** Outgoing messages now
  get a monotonic id, so two sent in quick succession are no longer mistaken for
  one another.
- **Unread counts follow device identity, not display name**, so peers sharing a
  display name no longer miscount notifications.
- **A private group keeps working when a single frame is malformed.** One bad
  frame no longer halts delivery, and a re-applied membership change is ignored
  instead of erroring.
- **Stricter invite validation.** An invite fingerprint must be a properly
  anchored, well-formed value before it's accepted.
- **Corrupted local data fails safe.** One unparseable line in stored history is
  skipped instead of dropping the whole conversation, and a corrupted MLS
  snapshot surfaces an error instead of silently emptying secure storage.
- **Keyboard focus stays inside open dialogs** — the focus trap now ignores
  `aria-hidden`/`inert` content.

## [0.2.9] - 2026-06-17

### Fixed
- **Voice messages can be recorded on macOS.** The recorder only offered the
  WebM/Ogg Opus containers, which the macOS WebView (WebKit) cannot capture, so
  it reported recording as unsupported and the microphone button never appeared.
  It now falls back to MP4/AAC on WebKit while keeping WebM/Opus on Windows, and
  the macOS bundle ships an `NSMicrophoneUsageDescription` so the system grants
  microphone access.
- **Attachments with a large preview are delivered again.** An attachment's
  manifest — including its inline thumbnail — rides a single gossip publish that
  caps at 64KB. A heavy thumbnail pushed the encrypted manifest past the cap, so
  the peer silently never received it even though the sender saw the message as
  sent. Oversized thumbnails are now dropped from the manifest (the file is
  still downloadable in full), keeping every attachment under the transport
  limit.

## [0.2.8] - 2026-06-15

### Fixed
- **Private DMs no longer get stuck on "waiting" after the peer connects.** The
  MLS handshake (KeyPackage → Welcome) was published exactly once, before the
  Moss mesh link to the peer existed. Gossip does not buffer for an unmeshed
  peer, so on a fresh invite the handshake frame was routinely lost and the
  conversation hung on "waiting" even though the transport reported the peer as
  joined. The joiner now re-sends its KeyPackage until the handshake completes,
  and the creator caches and re-answers the Welcome, so discovery flapping or a
  slow mesh no longer deadlocks the dialog.
- **Waiting private-DM invites survive restart.** Creating an invite now persists
  the creator's MLS snapshot immediately, so a waiting DM session reappears
  after relaunch and discovery can continue instead of dropping the dialog.
- **Restored DMs become writable after inbound activity.** If an incoming
  encrypted message proves the peer is already in the MLS session, the runtime
  now reports the DM as ready instead of leaving the composer stuck in
  `waiting`.
- **Restored DMs wait for live Moss presence.** Historical MLS state no longer
  marks a DM writable by itself after relaunch; the composer waits until Moss
  reports a live peer, and unread notifications ignore locally-authored
  messages.

## [0.2.7] - 2026-06-14

### Added
- **Persistent history for public channels and private groups.** Channel and
  private-group conversations now survive an application restart, the same way
  private DMs already did — message history is restored on launch instead of
  starting empty.
- **Send retry for failed messages.** A message that fails to send can be
  retried; the retry state is persisted, and historical messages show their
  retry status after a restart so a stuck send is visible rather than silently
  lost.
- **Message metadata in the UI.** Grouped messages now show timestamps, and
  per-message metadata is exposed without cluttering the thread.
- **Browser demo gateway.** The app can run against a browser-safe native
  gateway fallback, allowing a no-install demo in the browser.
- **Clearer peer diagnostics.** Peer/connection diagnostics are reorganized into
  a more readable hierarchy.

### Fixed
- **Mobile UX pass.** Expandable conversation rail, full-screen mobile
  diagnostics, ordered mobile topbar controls, a stabilized and tighter compact
  chat header, compact composer and session rail, and reduced chrome on grouped
  messages — the small-screen layout no longer overflows or crowds the content.
- **Send failures are surfaced.** A failed chat send now reports the error to the
  user instead of failing quietly.
- **Invite validation feedback.** Invalid invites are explained more clearly, and
  onboarding invite validation is tightened.
- **No destructive browser dialog.** The native confirm dialog was replaced with
  an in-app confirmation; modal keyboard focus was improved.
- **Diagnostics moved into a drawer**, message security metadata was quieted, and
  the raw attachment file input is hidden behind the normal control.
- Added an app favicon.

### Changed
- Large internal refactor with no behavior change: chat orchestration, composer,
  message lists, session rail, voice-call orchestration, DM offer/lifecycle, the
  onboarding panel, and the diagnostics drawer were split into focused hooks and
  components. This is groundwork; users should see no functional difference.

## [0.2.6] - 2026-06-03

### Added
- **Outgoing call UI.** Placing a call now shows a "Calling…" overlay with the
  peer's name, a dial tone, and a cancel button while waiting for an answer
  (previously the caller saw nothing).

### Fixed
- **Call screens show the right name.** An incoming call now shows the caller's
  name, and the active/outgoing call overlay shows the peer's name — instead of
  the local user's own display name. The peer name is learned from inbound
  frames and restored after a restart.

### Changed
- The right-hand peer-status panel is now reliably scrollable and more compact
  (smaller type, tighter spacing) so it no longer overflows the window.

## [0.2.4] - 2026-06-03

### Fixed
- **Honest NAT reachability detection (peer flapping).** A node behind NAT was
  classified as publicly reachable ("open") from a single reflexive address —
  which is only the NAT's WAN IP — so peers kept attempting futile direct dials
  and the connection flapped (rapid `peer_joined`/`peer_left`). The Moss runtime
  (bumped to v0.3.1) now leaves reachability to an actual inbound probe and
  detects symmetric NAT from varying mapped ports.

### Note
- Two peers both behind symmetric NAT still require a relay/supernode to
  connect; correct detection lets Moss pick relay paths instead of looping on
  direct dials.

## [0.2.3] - 2026-06-03

### Fixed
- **Sending works again after a restart.** When the app reconnects, the mesh
  re-delivers already-consumed MLS messages; decrypting those fails by design
  ("secret deleted to preserve forward secrecy"). Because the inbound drain ran
  before every send, that expected error was surfaced as a *send* failure. The
  drain now drops an undecryptable/replayed frame and keeps going, so sending
  is unaffected.

### Changed
- **Deleting a conversation now removes it for good.** Closing a chat previously
  only dropped it from the in-memory list, so it reappeared on the next launch.
  It now purges the persisted session record, MLS snapshot and messages, and
  asks for confirmation first.

## [0.2.2] - 2026-06-02

### Fixed
- **Stable Moss node identity across restarts.** The Moss transport identity
  (libp2p key) was regenerated on every launch because the host never wired
  Moss's keystore, so after a restart a peer saw a brand-new peer-id and the
  connection flapped (rapid `peer_joined`/`peer_left`) instead of
  re-establishing. The identity is now persisted in the encrypted store
  (AES-256-GCM) and reused on restart.

## [0.2.1] - 2026-06-02

### Fixed
- **Invite joiner's chat history now survives restart.** The peer who *accepted*
  an invite only obtains its MLS group after processing the creator's Welcome,
  so the session record written at accept time kept an empty group-id
  placeholder and could not be reloaded — the whole conversation was silently
  dropped on the next launch. The record is now refreshed once the group is
  established. (The invite *creator* was unaffected.)

### Changed
- Added a quality-gated CI pipeline (rustfmt, Clippy `-D warnings`, typecheck,
  vitest, cargo-nextest with retries) and a Windows release pipeline that builds
  and attaches installers. The Rust toolchain is pinned via `rust-toolchain.toml`.

## [0.2.0] - 2026-06-02

### Added
- **Encrypted persistent chat history.** Private-DM conversations now survive
  application restarts. Message history and MLS session state are stored
  encrypted at rest in a local redb database.
- **Full MLS session continuity.** The OpenMLS group state of each session is
  snapshotted and restored on startup (via `MlsGroup::load`), so an existing
  end-to-end-encrypted conversation keeps working after a restart with no
  re-invite or re-handshake.
- **Attachment & voice messages persist.** Attachment descriptors are stored and
  re-rendered from the local cache on restart; cached files (including the
  sender's own) open/play immediately. Voice-message metadata is preserved.
- **Call log persists.** Completed/missed call events keep their timestamp and
  duration across restarts.

### Security
- At-rest encryption uses **AES-256-GCM** with a random 96-bit nonce per record.
- The 256-bit data-encryption key (DEK) is stored in the **OS keychain** (Windows
  Credential Manager) and never written to disk in plaintext.
- **Fail-closed:** if the keychain or database is unavailable the app runs
  in-memory only and never falls back to writing unencrypted data. A transient
  keychain failure on a machine with an existing database is refused rather than
  silently minting a new key (which would orphan prior history).

### Known limitations
- Auto re-download of a received attachment that is **not** in the local cache is
  not possible from persisted data alone (the chunk-crypto manifest is not
  persisted and MLS forward secrecy prevents re-decrypting the original offer).
  Such an attachment re-renders as a bubble and downloads only if the peer
  re-offers it on reconnect.
- Channels and private groups are not yet covered; this release targets private
  DMs.
- Secure erasure of stale overwritten bytes in the database file is out of scope.

[0.2.8]: https://github.com/redstone-md/mosh/releases/tag/v0.2.8
[0.2.7]: https://github.com/redstone-md/mosh/releases/tag/v0.2.7
[0.2.0]: https://github.com/redstone-md/mosh/releases/tag/v0.2.0
