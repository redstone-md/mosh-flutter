# Desktop linking, issue 23

## Problem and scope

Two independent desktop installations must become devices of one Mosh user.
Keep each installation's Moss identity, device keys, MLS state, contacts and
history. Deliver QR import, trusted approval, private signed membership,
persistence and honest failure states. DM sync and revocation are later issues.

## Existing boundaries

The bridge owns singleton runtimes over SharedMossNode and Persistence.
Moss identity and MLS snapshots are already encrypted in redb. Moss exposes
directed streams and peer-id discovery. Stream 2 carries attachments.
Settings already has section navigation, Riverpod and localized fields.

## Options

- Clone the existing installation. Rejected, this copies transport and MLS keys.
- Publish the device list through a gossip room. Rejected, directed traffic
  keeps the list out of mesh-wide distribution.
- Add a server or wallet. Rejected, pairing must work free over Moss.
- Use a one-time random QR secret, existing AES-GCM and Ed25519 libraries,
  directed Moss stream 3 and a signed authorization chain. Chosen.

## Chosen direction

The new desktop creates a five-minute QR containing its own public device
descriptor, a random request id and a 256-bit secret. The trusted desktop
imports a QR image or the same link text. It sends its signed roster over
an encrypted stream. The new desktop proves possession of its device key
and displays a transcript-bound code. The trusted user enters that code
to authorize exactly that descriptor. Each device keeps its own private key.

The first device's public signing key anchors the Mosh user id. Genesis and
each addition are domain-separated Ed25519 signatures. An addition includes
the previous roster digest and is signed by a device in that roster. Verify
the whole chain, uniqueness and the expected extension before accepting it.
For this ticket updates are serialized by the trusted desktop. General
concurrent update/revocation rules belong to issue 27, not this protocol.

An encrypted single-row device-link table holds local signing material,
the verified roster and an approved delivery journal. Preserve all old tables.
Persist authorization before sending it and keep retrying the same approved
packet until the new desktop acknowledges its durable save. A saved receipt
allows a duplicate packet to be acknowledged after restart without adding
another device. Unapproved QR state is memory-only and dies on restart.

## Risks and decisions

- Possession of a QR image is sensitive. Show expiry; never log it.
- A replaced whole QR is a different device. The code must be read from the
  intended new desktop and checked in Rust on the trusted desktop.
- Signed membership needs strict signature verification, explicit versioning
  and parent digests. Reject malformed, stale and unrelated chains.
- An installation with existing chats cannot silently replace its user.
  Only a fresh, single-device installation can join another user.
- Approval can outlive connectivity. Show success only after durable remote
  acknowledgement on the trusted side, and retain the delivery journal.
- The new identity does not change existing org peer-id authority.
- Use qr_flutter and zxing2 for display/image decoding. Existing image and
  file_picker packages handle image bytes and desktop selection.

## References

- https://github.com/redstone-md/mosh-flutter/issues/23
- https://support.signal.org/hc/en-us/articles/360007320551-Linked-Devices
- docs/ADR/0011-secure-storage-and-threat-model.md
- docs/ADR/0026-one-node-a-transport-seam-and-a-dm-outbox.md
- docs/ADR/0027-attachments-ride-moss-streams.md
