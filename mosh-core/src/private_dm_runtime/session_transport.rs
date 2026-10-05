//! Frame routing, peer authentication and handshake liveness.

use super::*;

impl PrivateDmSession {
    pub(super) fn handle_moss_message(
        &mut self,
        message: MossReceivedMessage,
    ) -> Result<(), PrivateDmRuntimeError> {
        if self.has_seen_message(&message) {
            return Ok(());
        }
        if message.channel == self.control_channel {
            self.handle_control(message.payload)
        } else if message.channel == self.data_channel {
            self.handle_data(message.payload)
        } else if message.channel == self.blob_channel {
            self.handle_blob(message.payload)
        } else {
            Ok(())
        }
    }

    pub(super) fn has_seen_message(&mut self, message: &MossReceivedMessage) -> bool {
        // Control frames are exempt. The handshake's entire recovery mechanism
        // is re-sending the identical KeyPackage until the peer answers, and
        // this dedup keys on the payload hash — so every retransmission after
        // the first was dropped here, before handle_control ever saw it. The
        // re-answer path written precisely for a lost Welcome was therefore
        // unreachable, and a session whose first Welcome went missing hung on
        // "waiting" forever. Measured on a live pair: 85 KeyPackages published,
        // exactly one delivered, zero re-answers.
        //
        // Safe because every control branch is idempotent — each checks
        // `peer_joined` before acting. Data frames still dedup: those are what
        // would otherwise double up in the message history.
        //
        // Blob frames are exempt for the same reason as control. A receiver
        // that never got chunk 7 asks for chunk 7 again, and that request is
        // byte-identical to the one before it, so the sender dropped every
        // repeat here and never re-served — one lost chunk hung the transfer
        // for good. Users saw exactly that at 63%, 32% and 0%. Re-served chunk
        // frames are byte-identical too, so they need the same exemption.
        // Idempotent on both sides: serve_chunks just re-encrypts, and
        // ingest_chunk answers Duplicate for a chunk already held. What stops
        // the repeats from becoming a flood is the in-flight window in
        // next_chunk_request, not this set.
        if message.channel == self.control_channel
            || message.channel == self.blob_channel
            || self.devices_live()
        {
            return false;
        }
        self.seen.seen_before(&message.channel, &message.payload)
    }

    /// Remember the peer's display name from an inbound frame's `from_device`.
    pub(super) fn note_peer_name(&mut self, from_device: &str) {
        if from_device.is_empty() || from_device == self.device_id {
            return;
        }
        if self.peer_display_name.as_deref() != Some(from_device) {
            self.peer_display_name = Some(from_device.to_string());
        }
    }

    /// Remember the peer's moss peer id from the latest frame that carries it.
    /// Latest wins: a peer that restarts without a persisted moss identity
    /// re-handshakes under a fresh peer id, and pinning the first one would
    /// keep asking the transport for a dead id.
    pub(super) fn note_peer_moss_id(&mut self, id: Option<String>) {
        if let Some(id) = id {
            if self.peer_moss_id.as_deref() != Some(id.as_str()) {
                self.peer_moss_id = Some(id);
                self.record_dirty = true;
            }
        }
    }

    /// The counterpart's handshake frame arrived: the session is no longer
    /// waiting for somebody to show up, and our Hello is due at once.
    pub(super) fn note_handshake_frame(&mut self) {
        self.peer_joined = true;
        self.state = next_state(self.state, SessionEvent::HandshakeFrame);
        self.last_hello_send_ms = 0;
    }

    /// A frame decrypted, so the counterpart is alive and holds the group.
    /// This is the only way into `Connected`.
    pub(super) fn note_authenticated_frame(&mut self, from_device: &str) {
        self.note_peer_name(from_device);
        if self.crypto.is_ready() {
            self.peer_joined = true;
            let before = self.state;
            self.state = next_state(before, SessionEvent::AuthenticatedFrame);
            self.authenticated_since_tick = true;
            // Only the change into Connected is news. Written on every frame,
            // the line read like a reconnect every few seconds.
            if before != DmSessionState::Connected {
                dlog::write(
                    LogLevel::Info,
                    kinds::HANDSHAKE,
                    &self.session_id,
                    &format!("session connected (was {before:?})"),
                );
            }
        }
    }

    /// True when a pending KeyPackage should be re-published: the handshake is
    /// not complete, we still hold the payload, and the throttle window elapsed.
    pub(super) fn handshake_resend_due(&self, now_ms: u64) -> bool {
        !self.peer_joined
            && self.pending_key_package.is_some()
            && now_ms.saturating_sub(self.last_handshake_send_ms) >= HANDSHAKE_RESEND_MS
    }

    /// The single outbound chokepoint for control/data/blob frames. A Data
    /// frame is the user's message and carries a delivery status, so a
    /// refusal has to reach the caller. Control and Blob frames repeat on
    /// their own cadence and report nothing, so "no peers yet" is not news
    /// for them; every other failure still comes back.
    pub(super) fn route_send(
        &self,
        kind: ChannelKind,
        payload: &[u8],
    ) -> Result<(), PrivateDmRuntimeError> {
        let channel = kind.channel_for(&self.session_id);
        if payload.len() > crate::conversation::MAX_PUBLISH_BYTES {
            return Err(PrivateDmRuntimeError::PayloadTooLarge);
        }
        if self.devices_live() {
            return self.route_device_frame(&channel, payload);
        }
        self.persist_device_crypto()?;
        // Device-enabled sessions can bootstrap over the same directed carrier.
        if let Some(peer) = self.peer_moss_id.as_deref().filter(|peer| {
            self.membership.is_some() && self.transport.reach(peer) != PeerTransport::None
        }) {
            if let Some(frame) = crate::stream_transport::frame_for_channel(&channel, payload) {
                if self.transport.send_to_peer_stream(peer, &frame).is_ok() {
                    return Ok(());
                }
            }
        }
        match self.transport.publish(&self.mesh_id, &channel, payload) {
            Ok(()) => Ok(()),
            Err(PublishError::NoPeers(_)) if kind != ChannelKind::Data => Ok(()),
            Err(error) => Err(PrivateDmRuntimeError::Moss(error.to_string())),
        }
    }

    /// Hand the counterpart's moss id to the transport as an explicit connect
    /// target. The substrate is room-blind, so organic discovery only reaches
    /// the counterpart by chance; the explicit target is dialed immediately
    /// and retried by moss's maintenance loop until connected (direct first,
    /// then its own relay). One call per id value: moss keeps the
    /// registration, and a peer that re-handshakes under a fresh identity
    /// re-registers on the id change. Driven by the same ~1s drain tick as
    /// pump_handshake.
    pub(super) fn pump_peer_connect(&mut self) {
        self.connect_devices();
        let Some(id) = self.peer_moss_id.clone() else {
            return;
        };
        if self.connect_requested_for.as_deref() == Some(id.as_str()) {
            return;
        }
        match self.transport.connect_peer(&id) {
            Ok(()) => {
                dlog::write(
                    LogLevel::Info,
                    kinds::CONNECT,
                    &self.session_id,
                    &format!("connect_peer requested for {id}"),
                );
                self.connect_requested_for = Some(id);
                self.last_connect_outcome = Some(ConnectOutcome::Requested);
            }
            // Leave connect_requested_for unset so the next tick retries the
            // registration itself (e.g. node not started yet during rehydrate).
            Err(error) => {
                dlog::write(
                    LogLevel::Error,
                    kinds::CONNECT,
                    &id,
                    &format!("connect_peer failed: {error}"),
                );
                self.last_connect_outcome = Some(ConnectOutcome::Failed);
            }
        }
    }

    /// How the counterpart is reachable right now, or `None` before its id is
    /// known.
    pub(super) fn reach(&self) -> PeerTransport {
        self.reach_by(|id| self.transport.reach(id))
    }

    /// The same answer read from one mesh report, so every peer in it is
    /// judged against the same moment.
    pub(super) fn reach_in(&self, info: &MeshInfo) -> PeerTransport {
        self.reach_by(|id| transport::reach_of(id, info))
    }

    pub(super) fn reach_by(&self, reach: impl Fn(&str) -> PeerTransport) -> PeerTransport {
        if let Some(best) = self.peer_device_reach(&reach) {
            return best;
        }
        self.peer_moss_id
            .as_deref()
            .map_or(PeerTransport::None, reach)
    }

    /// Best-effort retransmit of the joiner's KeyPackage while the MLS handshake
    /// is still incomplete. Driven by the inbound drain loop (≈1/s), throttled
    /// to HANDSHAKE_RESEND_MS. Once the peer has joined the pending payload is
    /// dropped so nothing is re-sent.
    pub(super) fn pump_handshake(&mut self, now_ms: u64) {
        if self.peer_joined {
            self.pending_key_package = None;
            return;
        }
        if !self.handshake_resend_due(now_ms) {
            return;
        }
        let Some(payload) = self.pending_key_package.clone() else {
            return;
        };
        self.last_handshake_send_ms = now_ms;
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// Say hello until the counterpart answers with anything authenticated,
    /// then keep a quiet Connected session alive with one every
    /// KEEPALIVE_MS. Our side of the handshake is done and MLS is ready, so
    /// the counterpart can decrypt this the moment it holds the group;
    /// receiving it is its proof that we are here, and its reply is ours.
    /// A Hello from the counterpart is answered here too, but never inside
    /// our own cadence: two sides would otherwise ping-pong forever.
    pub(super) fn pump_hello(&mut self, now_ms: u64) {
        let answer = std::mem::take(&mut self.hello_answer_due);
        if !self.can_encrypt_for_peer() {
            return;
        }
        let since_send = now_ms.saturating_sub(self.last_hello_send_ms);
        let due = if self.state == DmSessionState::Connected {
            let quiet = now_ms.saturating_sub(self.last_authenticated_rx_ms) >= KEEPALIVE_MS;
            quiet && since_send >= KEEPALIVE_MS
        } else {
            since_send >= HANDSHAKE_RESEND_MS
        };
        if due || (answer && since_send >= HANDSHAKE_RESEND_MS) {
            self.send_hello(now_ms);
        }
    }

    /// Our side of the handshake is done and there is a group to encrypt
    /// for.
    pub(super) fn can_encrypt_for_peer(&self) -> bool {
        self.peer_joined && self.crypto.is_ready()
    }

    /// One Hello: our moss id, MLS-encrypted so only the counterpart can read
    /// it and nobody else can forge it. Loss is fine, the pump repeats it.
    pub(super) fn send_hello(&mut self, now_ms: u64) {
        let Some(moss_peer_id) = self.transport.local_peer_id() else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(moss_peer_id.as_bytes()) else {
            return;
        };
        let envelope = ControlEnvelope::Hello {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            hello_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        self.last_hello_send_ms = now_ms;
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// Tell a joined counterpart our moss peer id while we do not know theirs.
    /// The counterpart answers with an encrypted Hello, which authenticates
    /// its address. Announcements stop once that address is known.
    pub(super) fn pump_peer_announce(&mut self, now_ms: u64) {
        if !self.peer_joined || self.peer_moss_id.is_some() {
            return;
        }
        if now_ms.saturating_sub(self.last_peer_announce_ms) < PEER_ANNOUNCE_RESEND_MS {
            return;
        }
        self.last_peer_announce_ms = now_ms;
        if let Err(error) = self.publish_peer_announce() {
            dlog::write(
                LogLevel::Error,
                kinds::ANNOUNCE,
                &self.session_id,
                &format!("peer announce failed: {error}"),
            );
        }
    }

    pub(super) fn publish_peer_announce(&self) -> Result<(), PrivateDmRuntimeError> {
        let Some(moss_peer_id) = self.transport.local_peer_id() else {
            return Ok(());
        };
        let envelope = ControlEnvelope::PeerAnnounce {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            moss_peer_id,
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)
    }
}
