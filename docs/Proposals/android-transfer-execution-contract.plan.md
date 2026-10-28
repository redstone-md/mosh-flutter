# Android attachment execution contract — IVO-145

Status: implementation boundary agreed with the Android owner; OS integration and
independent-installation acceptance remain required. This extends the approved
background execution contract without introducing another runtime or downloader.
IVO-146 is the separate process/reboot/first-unlock lifecycle slice; transfer
checkpoint recovery below coordinates with it and does not replace its acceptance.

## Native source of truth

An attachment offer is metadata. A sender's `Available` attachment means that its
own original is cached, not that another installation received it. Background
waiting never admits original or auxiliary-preview downloads automatically.
Explicit Download and explicit playback both admit user work; repeated local HTTP
range requests cannot create new work after the application becomes noninteractive.
An already admitted transfer keeps its original admission when the app hides.

Each admitted user operation has an opaque random `transfer-<32 lower hex>` ID,
persisted with its target, direction, attachment manifest, native state and durable
progress in the existing encrypted `background_delivery` namespace. Android intents
and notifications carry only that opaque ID. Chat IDs, paths, attachment keys and
names stay inside the encrypted native owner. A download is not admitted merely
because an offer, preview or restored chat widget exists.

States distinguish prepared, waiting for receiver, waiting for OS execution,
running, paused, complete, failed and cancelled. Scheduling accepted is not running.
A receiver marks complete only after all authenticated chunks verify, the original
hash matches and the completed file is committed. A sender tracks each requesting
receiver separately and completes that upload only after an authenticated receipt
for that exact request. It never interprets a transport write as remote completion.
Group/channel publication has no fixed complete recipient set.

The durable checkpoint contains only authenticated received chunks, stored under
the installation DEK, plus the admission and manifest binding. Request timers and
socket handles are rebuilt, not serialized. Restart requests only missing chunks;
a corrupt/inconsistent checkpoint fails closed without redownloading automatically.
Cancel durably revokes execution and keeps verified partial bytes for an explicit
Resume. Forget/delete removes the execution admission and partial checkpoint through
the existing kind cleanup. Final originals retain the existing attachment store
behavior; this proposal does not claim encryption of completed local originals.

## Android execution boundary

One `app.mosh.mosh/waiting` channel owns these methods:

- `beginUserTransfer {id, direction: upload|download, estimatedBytes}` is invoked
  during the actual visible user action. Its boolean result acknowledges scheduler
  acceptance, not a running job. A refusal remains visible native state.
- `setUserWork` includes native `transfers: [{id, direction, state,
  completedBytes, totalBytes}]` together with the existing intent revision. There
  is no second Dart count of guessed work.
- `beginDeferredTransfer {id, direction, estimatedBytes}` schedules an ordinary
  constrained network JobScheduler job only after native validates a real late
  peer request against a durable local Send admission. It is not UIDT and may
  wait for Android quota/network availability. No periodic self-restart is added.
- `readTransferExecution` returns an Android revision and actual per-ID execution
  grants `{id, generation, allowed, reason}`. `transferExecutionChanged` is a
  coalesced hint; the application owner re-reads the same source of truth.
- `takeTransferActions` reads a bounded durable queue of
  `{id, action: cancel|resume, revision}` without removing entries.
  `acknowledgeTransferActions [{id, revision}]` removes only the exact accepted
  revisions after native durable cancellation/resume. A failed commit remains
  queued. `transferActionsChanged` carries no target. Resume requires an eligible
  visible action; an OS constraint loss is not a user cancellation.

For Android 14+, JobService starts the UIDT notification before publishing an
execution grant. Earlier versions use the existing process's correctly typed
`dataSync` foreground service. Neither starts a second Flutter engine/native node.
Native permits byte requests/serving while the Activity is genuinely interactive
or while the corresponding current OS grant exists. Monotonic per-ID generation
and process incarnation reject stale late grants after Stop/reclamation.
`MoshNative.setTransferInteractive(Boolean)` synchronously publishes actual normal
Activity/access visibility, excluding locked call-only entry. It defaults to false
and cannot be overridden by a stale Dart interaction mirror. Cold native code has
no automatic-download permission and no OS execution grants.

An OS constraint interruption durably pauses progress and releases its grant;
Android owns subsequent eligible rescheduling. A user OS Stop/Force stop is not
restarted by an alarm, receiver, timer or connectivity callback. Reboot waits for
first device unlock and an eligible entry. Finishing a transfer restores saved
waiting Off, rather than enabling it. An app Stop stops waiting, not an already
admitted and still OS-eligible transfer.

## Receiver-pull timing

An outgoing offer may be fetched long after Send. A pending offer alone cannot
hold a UIDT job or Active mesh forever. Android restricts starting a new UIDT from
a later invisible remote request. A native-validated late request with durable
local Send admission instead authorizes one bounded ordinary JobScheduler network
job. Android may defer it for constraints/quota; progress truthfully reports
waiting for execution. It uses the same retained owner, encrypted checkpoints and
per-ID actual execution grants. When the requester becomes unavailable or its
bounded pending request expires, the job ends without claiming upload completion.
The durable original remains available for a later real request. Native retry
backoff stays attached to pending request work, not a perpetual watchdog.

Explicit visible Send, Download or Resume uses UIDT on Android 14+ (typed foreground
execution earlier). App Stop does not cancel an already admitted transfer; OS user
Stop/Force stop is respected and never schedules another deferred job. A later
foreground resume can re-admit work without resetting the user's waiting choice.

## Verification

Use the existing independent public bridge/Moss fixtures for real offers, chunk
progress, completion, interruption, exact resume, duplicate receipts and receiver
hash verification. Test native automatic admission under waiting/Off directly.
Android checks observe actual UIDT/service lifecycle, notification/action behavior,
constraint interruption and user Stop on a phone; compiling the boundary does not
prove OEM/Doze or battery acceptance. Keep capture and chat contents out of logs.

## Request and completion authentication

The optional chunk-request execution metadata carries a random receiver token,
request/complete/ack phase, bounded signed expiry and an existing `MessageOrigin`
Ed25519 proof. Its domain binds the exact conversation, attachment, indices,
receiver signer, token and phase. DM/group owners additionally check current MLS
membership; organization groups also check the current organization roster.
Public channel readers have no private membership claim. Possessing an offer key
or changing the participant/fingerprint wrapper cannot forge another receiver's
completion. A recipient signs Complete only after verified atomic file storage;
it is an authenticated acknowledgement, not a claim to cryptographically prove
that a malicious recipient retained its file. The sender signs its exact Ack.
Receiver facts survive sender restart in the same encrypted transfer record.

Upload byte progress counts unique chunks accepted by the existing chunk
transport; an explicit NoPeers refusal does not advance progress. Only the authenticated exact
receiver acknowledgement can set Complete. Known concurrent receiver requests
are tracked independently; a channel/group does not promise an enumerated set of
all possible readers. Pending requests expire after two minutes. Deferred job
attempts coalesce with a three-minute minimum gap; no pending offer alone
schedules work. Incorrect device wall clocks can reject the signed request expiry.

## Focused implementation checks

The real-file tests verify cancellation/resume, partial checkpoints through a
native-owner restart, exact receiver signatures/tokens, forged other-member
completion, duplicate receipt idempotence, sender restart and transactional
conversation deletion. An authenticated short chunk was reproduced as a false
partial-progress advance and now fails before checkpoint admission. Android
arm64 Rust compilation and the Dart/OS-channel tests validate the boundary;
actual UIDT/Doze/OEM behavior remains part of handset acceptance.

The request-admission match, checkpoint replay and transaction constructors retain
one ordered authorization/commit boundary and exceed 50 lines after rustfmt.
The complete independent file/restart proofs also exceed 50 lines so their
positive and negative controls remain together. New authored files stay below
400 lines; no new state-owning type declaration exceeds 200 lines.

The OS status snapshot uses a private encrypted current-work index: pending
running/waiting-execution/paused records plus at most 64 recent quiescent records.
Historical local-Send and receiver facts remain addressable but are not decrypted
on every background hint. Verified download frames commit in batches of up to
64 chunks through existing protocol turns, on cancellation and before final file
commit; a crash may require requesting at most 256 KiB again per active download.
This avoids a separate durable disk transaction for each 4 KiB network chunk.
