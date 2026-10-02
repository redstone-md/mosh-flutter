# Device linking

Open Settings → Devices on both installations. On the trusted device, choose
**Link another device → Create linking QR**. On the new installation, choose
**Connect this device** and scan that QR with the Android camera, choose its
image, or paste its private link. The new device displays a 12-character code.
Enter it on the trusted device and approve. Keep both online until the trusted
device shows Device linked. The invitation is single-use and expires after five
minutes. Keep it private.

The Android scanner uses bundled `mobile_scanner`, so scanning does not require
a model download. Camera permission is requested only when opening the scanner;
returning to the form always leaves image/link import available. The plugin owns
camera startup, background pause, foreground return and disposal. Desktop uses
image/link import. No platform or online status is inferred from device names.

The QR renderer uses whole pixel modules so a desktop screenshot stays
readable. The importer decodes its image off the UI thread and rejects files
over 10 MiB or images over 16 megapixels.

```mermaid
flowchart TD
    Trusted[Trusted device creates v2 QR] --> Import[New device scans or imports QR]
    Import --> Join[New device sends its signed independent descriptor]
    Join --> Freeze[Trusted device freezes the first candidate]
    Freeze --> Proof[Encrypted signed roster offer and device-key proof]
    Proof --> Code[Fresh desktop shows code]
    Code --> Approve[Trusted user enters code and approves]
    Approve --> Save[Save signed device list on both desktops]
    Save --> Ack[Fresh desktop acknowledges durable save]
    Ack --> Done[Both show the same Mosh user and device list]
    Proof --> Decline[Decline or expiry adds no device]
```

The existing desktop keeps its Moss peer-id, contacts, MLS state and history.
The linked desktop keeps its own signing key, Moss identity and connections.
The list restores after restart. An installation with existing conversations
cannot join another user; it can approve a fresh desktop instead.

Pairing is free and needs no wallet. Linked installations join existing text DMs
with independent MLS keys, import available history and recover missed epochs
and text after reconnecting. See [Private DM](private-dm.md) and the
[Android foreground flow and physical verification](android-linked-dm.md).

## Remove a linked desktop

Choose Remove beside another desktop and confirm its name. The signed roster
removal is saved before delivery. Affected DMs remove that installation's
exact MLS leaf and retry the same durable transition to remaining participants.
Pending means a remaining participant has not saved its removal epoch; Applied
means all affected remaining participants have acknowledged that save. An
offline participant must reconnect to apply it. The removed desktop need not
acknowledge the transition.

```mermaid
flowchart TD
    Confirm[Confirm another desktop by name] --> Roster[Save signed removal]
    Roster --> Remove[Remove that exact MLS leaf]
    Remove --> Save[Save epoch and delivery journal atomically]
    Save --> Pending[Pending while remaining participants are offline]
    Pending --> Ack[Remaining participants save and acknowledge epoch]
    Ack --> Applied[Applied: future text uses the removal epoch]
    Roster --> Archive[Removed desktop keeps received history]
    Archive --> QR[Fresh QR and human code approval for the same user]
    QR --> Join[Fresh independent MLS join]
```

The removed desktop keeps already received history readable and cannot send
or request new sync in those DMs. This does not erase its local history. Old
QRs, approvals and signed roster prefixes cannot restore access. Request
access again on that desktop and scan a fresh QR from an authorized device;
the authorized device must approve its new code. Its old history stays under its own storage key, and
its DM joins use new MLS keys. Retained conversations cannot be used to join
a different user. See [ADR 0033](../ADR/0033-dm-device-revocation.md).

## Failures and recovery

Wrong codes do not authorize a device. Expired, cancelled, substituted and
replayed requests cannot add another device. A whole replaced QR names a
different authorizer; read it only from your trusted device. Approve only a code
read from the intended new installation. After the first valid join request, a
second scanner cannot replace the candidate, obtain its code or gain access.
An interrupted exchange reports a connection error. An unused QR needs to be
created again after restart. Once both desktops have exchanged their proof,
the new desktop restores that pending request until its five-minute expiry.
Once approval is saved, it cannot be cancelled
as though it never happened. The core retries the saved authorization until
the new desktop acknowledges its save. Removing an approved entry uses the
separate signed removal flow above.
If the new desktop never receives that approval before its request expires,
the trusted desktop keeps the approved entry and reports incomplete delivery.
It cannot silently undo a signed authorization.
Cancellation records that request until expiry, so losing its rejection packet
does not let either installation reuse the consumed invitation. Starting a conversation
on a desktop waiting to join cancels its pending request and keeps its own user.
The online trusted desktop receives that rejection and cannot approve its code.

The list is signed and sent only through an encrypted directed Moss stream.
It is never published through gossip. The local record uses the installation's
existing encrypted redb store. See [ADR 0029](../ADR/0029-private-desktop-device-linking.md)
for the exact authorization and verification rules.

New imports require v2. Older QR invitations are rejected with instructions to
create one on the trusted device. Existing identities, rosters and history keep
their formats. Authenticated v1 pending exchanges restore only their pinned peer
and base roster until expiry; already committed v1 deliveries and receipts can
finish after either side upgrades. No fresh v1 request can be started or imported.

## Tests

- `node scripts/moss-test.mjs --test device_link_flow`
  runs separate installations with real Moss, independent signing/transport
  keys and databases. It checks approval, refusal, QR mutation/replay, restart
  and an existing text DM with a third installation. Automatic discovery uses
  a real local tracker. The wrapper installs its pinned tool outside the repo.
- `node scripts/moss-test.mjs --test device_link_invitation` checks candidate
  freezing against another real scanner, with a fresh-invitation positive control,
  and rejection of v1 invitations without changing the installation's identity.
- `node scripts/moss-test.mjs --lib an_already_approved_v1_delivery` checks old
  persisted pending exchanges, approval delivery and duplicate receipts using
  independent processes and a separately encoded v1 fixture. Fixtures are test
  only; no private persistence method is exposed through production APIs.
- `cargo test --manifest-path mosh-core/Cargo.toml --test device_link_identity`
  proves persistent identity and unchanged old history/transport records.
- `cargo test --manifest-path mosh-core/Cargo.toml device_link::protocol_tests`
  checks strict signed membership, authorized delegation, packet integrity,
  ciphertext confidentiality, removal authority and expiry at the byte-decoding boundaries.
- `cargo test --manifest-path mosh-core/Cargo.toml --lib fresh_approval_completes`
  proves a signed roster notice arriving before the matching fresh approval
  cannot interrupt that approval or revive a consumed request after removal.
- `node scripts/moss-test.mjs --lib another_identity_owner_can_remove` verifies
  authorizer removal during QR display, approval entry and committed delivery.
  A separate identity owner writes the signed removal through the same encrypted
  CAS boundary used by DM adoption.
- `node scripts/moss-test.mjs --lib a_late_approval_cannot_restore` verifies
  Add notice → newer Remove → delayed Approved, both through notices and when
  DM commits the removal before its duplicate notice. A delayed approval cannot
  roll back that signed removal; a pinned prior removal still permits fresh rejoin.
- `flutter test test/features/device_link/qr_image_test.dart` renders a real
  QR and decodes its image with the desktop importer.
- After `cargo build` and the real-process tests above,
  `node scripts/moss-test.mjs --native-ui` drives the actual Devices
  screen through linking, removal cancellation, confirmed removal and fresh
  approval on the revoked installation using
  the native bridge and a separate Moss process. No bridge or
  service doubles are used. CI runs this in its independent Windows native
  linking job, with the same real tracker as the independent-process checks.
  This job builds the Rust library and peer without compiling the desktop app;
  the separate desktop integration job still builds and tests slice one.
- `flutter test native_test/native_peer_io_test.dart` checks the test helper
  with a real subprocess: background stdout must not prevent progress between
  requests, and exiting before a reply must report the existing EOF error.

- `flutter test test/features/device_link` checks both role choices, eligibility,
  approval controls, actual full-size QR rendering/decoding and 320/800-pixel
  layouts with enlarged text. Camera hardware is substituted at the plugin's
  public platform seam only, to check empty/repeated captures, permission denial,
  unsupported cameras, background return and exit. Authorization still uses the
  real native bridge in the UI probe.

New production code requires 80% line coverage; branch coverage is required
where the toolchain provides it. Windows/macOS installers need their own
hosts; Linux verifies the native bridge and protocol here.

To probe the live public Moss network, run the same suite directly with
`cargo test --manifest-path mosh-core/Cargo.toml --test device_link_flow`.
That probe depends on public tracker and relay availability. Neither mode
manually connects peers in the public bridge scenario. The local tracker
override only exists in debug builds.
The UI probe can also run directly with
`flutter test native_test/device_link_test.dart`.
