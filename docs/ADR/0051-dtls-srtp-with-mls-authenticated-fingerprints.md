# ADR 0051: DTLS-SRTP with MLS-authenticated fingerprints

Date: 2026-11-05.
Status: Accepted for MOSH-70.

The RingRTC engine disables DTLS and installs SRTP keys that Mosh derives
itself: each side puts an X25519 public key into its media description, MLS
authenticates the description, and HKDF over the shared secret and the
selected-pair binding yields one AES-256-GCM key per direction. That needs
SDES-style key installation, which Google removed from libwebrtc in M123
(`974044efca4f`, "Remove code for supporting SDES") and which only Signal's
fork keeps. The engine that replaces RingRTC (MOSH-70) uses upstream
libwebrtc without a fork.

## Decision

Media uses standard DTLS-SRTP. libwebrtc generates a fresh certificate per
call, its SHA-256 fingerprint is part of the SDP, and the SDP travels inside
the media description that MLS already authenticates and binds to the selected
call, devices and media session ([ADR 0043](0043-one-device-per-user-in-a-call.md)).
The DTLS handshake runs over Moss like every other media packet
([ADR 0044](0044-native-call-media-over-moss.md)). A peer whose certificate does
not match the authenticated fingerprint fails the handshake, so a relay or any
other party on the path cannot terminate DTLS.

Only AEAD SRTP profiles are offered; calls negotiate `AEAD_AES_256_GCM`, the
profile the RingRTC engine used. DTLS itself is 1.3.

## Consequences

- Equivalent guarantees: the media keys come from an ephemeral ECDHE exchange
  per call (forward secrecy), and only the device whose description MLS
  authenticated can complete it.
- Setup gains the DTLS handshake round trips over Moss. On a relayed path this
  delays first audio by a few hundred milliseconds.
- The engine's own key agreement (`mosh-media/engine/src/keys.rs`) is deleted
  with RingRTC.
- Old clients cannot talk to new ones; MOSH-70 already drops that compatibility.
