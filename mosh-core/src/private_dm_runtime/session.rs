//! The DM session: construction, restore, and the persist record.

use super::*;

impl PrivateDmSession {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn new(
        role: SessionRole,
        device_id: String,
        participant_id: String,
        session_id: String,
        mesh_id: String,
        fingerprint: String,
        invite_uri: Option<String>,
        listen_port: u16,
        static_peer: Option<String>,
        transport: Arc<dyn DmTransport>,
        crypto: MlsSessionCrypto,
        attachment_store: Arc<AttachmentStore>,
    ) -> Self {
        let control_channel = control_channel(&session_id);
        let data_channel = data_channel(&session_id);
        let blob_channel = blob_channel(&session_id);
        Self {
            role,
            state: DmSessionState::Pending,
            last_authenticated_rx_ms: 0,
            authenticated_since_tick: false,
            hello_answer_due: false,
            stream_backoff_until_ms: 0,
            device_id,
            participant_id,
            session_id,
            mesh_id,
            fingerprint,
            peer_moss_id: None,
            connect_requested_for: None,
            last_connect_outcome: None,
            invite_uri,
            listen_port,
            static_peer,
            peer_display_name: None,
            peer_joined: false,
            transport,
            crypto,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            control_channel,
            data_channel,
            blob_channel,
            transfer: Transfer::new(attachment_store),
            outbound_attempts: HashMap::new(),
            call: None,
            pending_key_package: None,
            pending_welcome: None,
            last_handshake_send_ms: 0,
            last_peer_announce_ms: 0,
            last_hello_send_ms: 0,
            peer_typing_until_ms: None,
            typing_gate: TypingGate::default(),
            peer_read_ids: Vec::new(),
            sent_read_ids: Vec::new(),
            dirty_outbound: Vec::new(),
            record_dirty: false,
        }
    }

    /// What a replayed history says about the handshake: the peer's display
    /// name comes back from an inbound message, and a session that had joined
    /// starts over as `Handshaking` — nothing from the counterpart has been
    /// seen since the restart, so it is not Connected until it proves itself.
    pub(super) fn note_restored_history(&mut self) {
        self.peer_display_name = self
            .messages
            .iter()
            .map(|message| message.from_device.as_str())
            .find(|name| !name.is_empty() && *name != self.device_id)
            .map(str::to_string);
        // Bob only ever has a group after the Welcome; Alice has one from the
        // start, so for her only an inbound message proves the handshake ran.
        let handshake_done = self.crypto.is_ready()
            && (matches!(self.role, SessionRole::Bob) || self.peer_display_name.is_some());
        if handshake_done {
            self.peer_joined = true;
            self.state = DmSessionState::Handshaking;
        }
    }

    /// Builds the persisted record from the live session. `group_id` reflects
    /// the current MLS group, so re-persisting after the joiner processes the
    /// Welcome replaces the empty placeholder written at accept time.
    pub(super) fn to_persisted_record(&self) -> contracts::PersistedSession {
        contracts::PersistedSession {
            role_is_alice: matches!(self.role, SessionRole::Alice),
            display_name: self.device_id.clone(),
            participant_id: self.participant_id.clone(),
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            fingerprint: self.fingerprint.clone(),
            invite_uri: self.invite_uri.clone(),
            signer_public: self.crypto.signer_public(),
            group_id: self.crypto.group_id_bytes().unwrap_or_default(),
            listen_port: self.listen_port,
            static_peer: self.static_peer.clone(),
            peer_moss_id: self.peer_moss_id.clone(),
            // Only ids of our own messages the peer read survive a restart:
            // the ids of the messages WE receipted are re-derivable from the
            // rehydrated history (the counterpart re-asks only when its
            // screen re-renders), and keeping just these keeps the record
            // small.
            read_message_ids: prune_read_ids(&self.peer_read_ids),
        }
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    pub(super) fn outbox(&mut self) -> Outbox<'_, ChatMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

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
        } else if wire::channel_call_id(&message.channel).is_some() {
            self.handle_voice_call_frame(&message.channel, message.payload)
        } else {
            Ok(())
        }
    }

    pub(super) fn handle_voice_call_frame(
        &mut self,
        channel: &str,
        payload: Vec<u8>,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call_id) = wire::channel_call_id(channel) else {
            return Ok(());
        };
        if let Some(call) = self.call.as_mut() {
            if call.call_id == call_id {
                call.push_frame(payload);
            }
        }
        Ok(())
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
        if message.channel == self.control_channel || message.channel == self.blob_channel {
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
        let Some(id) = self.peer_moss_id.clone() else {
            return;
        };
        if self.connect_requested_for.as_deref() == Some(id.as_str()) {
            return;
        }
        match self.transport.connect_peer(&id) {
            Ok(()) => {
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
        self.peer_moss_id
            .as_deref()
            .map_or(PeerTransport::None, |id| self.transport.reach(id))
    }

    /// Stamp the proof drained since the last tick, and admit the
    /// counterpart is gone once nothing authenticated arrived for the whole
    /// lost window. Moss's peer table plays no part: gossip carries a chat
    /// through other peers while moss lists no row for the counterpart, and a
    /// failed mesh report says nothing about the counterpart at all.
    pub(super) fn pump_liveness(&mut self, now_ms: u64, lost_window_ms: u64) {
        if std::mem::take(&mut self.authenticated_since_tick) {
            self.last_authenticated_rx_ms = self.last_authenticated_rx_ms.max(now_ms);
        }
        let silent_for = now_ms.saturating_sub(self.last_authenticated_rx_ms);
        if self.state == DmSessionState::Connected && silent_for >= lost_window_ms {
            self.state = next_state(self.state, SessionEvent::CounterpartLost);
        }
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
    /// Symmetric by construction: whichever side is missing the id keeps
    /// announcing, the other side answers with its own announce on receipt, and
    /// both stop as soon as they know.
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

    /// Send queued messages oldest first once our side of the handshake is
    /// done, so the ciphertext is at an epoch the counterpart holds. Moss's
    /// peer table is not asked: a room publish does not need a row for the
    /// counterpart, a publish with nobody to take it comes back `NoPeers`
    /// and leaves the text queued, and the resend + DeliveryAck loop covers
    /// a frame the transport took but lost. A refusal stops the pass, so a
    /// newer message never overtakes an older one. Returns the ids whose
    /// attempt changed so the runtime can persist them.
    pub(super) fn pump_outbox(&mut self) -> Vec<String> {
        if !self.can_encrypt_for_peer() {
            return Vec::new();
        }
        let mut changed = Vec::new();
        for message_id in queued_in_order(&self.outbound_attempts) {
            if let Err(error) = self.publish_queued(&message_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::OUTBOX,
                    &self.session_id,
                    &format!("queued message {message_id} stays queued: {error}"),
                );
                break;
            }
            changed.push(message_id);
        }
        changed
    }

    /// Encrypt one queued message at the current epoch, publish it, and settle
    /// it `Sent`. The bytes are recorded on the attempt so the auto re-sends
    /// replay the same ciphertext the counterpart dedups on.
    pub(super) fn publish_queued(&mut self, message_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let body = self
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(message_id))
            .map(|message| message.body.clone())
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let sent_at_ms = self
            .outbound_attempts
            .get(message_id)
            .map(|attempt| attempt.sent_at_ms)
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let ciphertext = self.crypto.encrypt(body.as_bytes())?;
        let envelope = DataEnvelope {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            message_id: Some(message_id.to_string()),
            sent_at_ms: Some(sent_at_ms),
            ciphertext_b64: encode(&ciphertext),
            resend: None,
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Data, &payload)?;
        if let Some(attempt) = self.outbound_attempts.get_mut(message_id) {
            attempt.publish_payload_b64 = encode(&payload);
            attempt.ciphertext_bytes = ciphertext.len();
        }
        self.outbox().settle(message_id, Ok(()), OnSent::Retain)?;
        Ok(())
    }

    /// Re-send user messages the peer has not acknowledged. Moss pubsub has
    /// no store-and-forward, so a frame published into a dead/half-open link
    /// vanishes; unacked Sent attempts re-publish every AUTO_RESEND_MS until
    /// the peer's DeliveryAck lands or AUTO_RESEND_MAX gives up (old client
    /// that never acks — the message keeps its Sent status). Returns the ids
    /// whose attempt state changed so the runtime can persist them.
    pub(super) fn pump_unacked_resends(&mut self, now_ms: u64) -> Vec<String> {
        if !self.peer_joined {
            return Vec::new();
        }
        let due: Vec<(String, String, u32)> = self
            .outbound_attempts
            .iter()
            .filter(|(_, attempt)| {
                attempt.delivery_status == MessageDeliveryStatus::Sent
                    && attempt.auto_resends < AUTO_RESEND_MAX
                    && now_ms.saturating_sub(attempt.last_send_ms) >= AUTO_RESEND_MS
            })
            .map(|(id, attempt)| {
                (
                    id.clone(),
                    attempt.publish_payload_b64.clone(),
                    attempt.auto_resends,
                )
            })
            .collect();
        let mut changed = Vec::new();
        for (message_id, payload_b64, auto_resends) in due {
            let Ok(payload) = decode(&payload_b64) else {
                continue;
            };
            // Bump the resend counter INSIDE the envelope so the re-sent
            // frame's bytes differ from the original — the receiver's
            // frame-level sha256 dedup would otherwise swallow the duplicate
            // before the re-ack path could run.
            let Ok(mut envelope) = serde_json::from_slice::<DataEnvelope>(&payload) else {
                continue;
            };
            envelope.resend = Some(auto_resends + 1);
            let Ok(bytes) = serde_json::to_vec(&envelope) else {
                continue;
            };
            // Only a re-send the transport took burns a slot — a refusal must
            // not exhaust the budget with zero frames on the wire.
            if self.route_send(ChannelKind::Data, &bytes).is_err() {
                continue;
            }
            if let Some(attempt) = self.outbound_attempts.get_mut(&message_id) {
                attempt.auto_resends += 1;
                attempt.last_send_ms = now_ms;
                // Session transition the field log carries: how many times a
                // message had to be re-sent before the ack arrived.
                dlog::write(
                    LogLevel::Info,
                    kinds::RESEND,
                    &self.session_id,
                    &format!("resend #{} of message {message_id}", attempt.auto_resends),
                );
                // At the cap the attempt STAYS: the filter above stops the
                // automatic loop, the message honestly keeps Sent (not
                // Delivered), and a manual retry still has its payload.
            }
            changed.push(message_id);
        }
        changed
    }

    /// Ids whose delivery state changed from inbound frames since the last
    /// drain — the runtime persists these rows.
    pub(super) fn take_dirty_outbound(&mut self) -> Vec<String> {
        std::mem::take(&mut self.dirty_outbound)
    }
}
