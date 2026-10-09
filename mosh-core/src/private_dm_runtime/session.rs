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
            invitation: None,
            deletions: crate::message_deletion::DeletionBook::new(
                format!("dm:{session_id}"),
                DM_HISTORY,
                None,
            ),
            history_last_rx_ms: 0,
            recovery_boot_ms: 0,
            recovery_pull_ms: 0,
            membership: None,
            device_signer: None,
            device_store: None,
            device_connect_requested: std::collections::HashSet::new(),
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
            logged_reach: PeerTransport::None,
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
            call_occupancy: Default::default(),
            call_ends: Default::default(),
            call_controls: Default::default(),
            call_admission_blocked: false,
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
            .invitation
            .as_ref()
            .and_then(|invite| invite.peer_name.clone())
            .or_else(|| {
                self.messages
                    .iter()
                    .map(|message| message.from_device.as_str())
                    .find(|name| !name.is_empty() && *name != self.device_id)
                    .map(str::to_string)
            });
        // Bob only ever has a group after the Welcome; Alice has one from the
        // start, so for her only an inbound message proves the handshake ran.
        let handshake_done = self.crypto.is_ready()
            && (matches!(self.role, SessionRole::Bob)
                || self.peer_display_name.is_some()
                || self
                    .invitation
                    .as_ref()
                    .is_some_and(|invite| invite.consumed)
                || self.has_restored_counterpart());
        if handshake_done {
            self.peer_joined = true;
            self.state = DmSessionState::Handshaking;
        }
    }

    fn has_restored_counterpart(&self) -> bool {
        self.membership
            .as_ref()
            .map_or(self.crypto.member_count() > 1, |membership| {
                membership.has_counterpart(&self.crypto.member_signers())
            })
    }

    /// Builds the persisted record from the live session. `group_id` reflects
    /// the current MLS group, so re-persisting after the joiner processes the
    /// Welcome replaces the empty placeholder written at accept time.
    pub(super) fn to_persisted_record(&self) -> contracts::PersistedSession {
        contracts::PersistedSession {
            invitation: self.invitation.clone(),
            membership: self.membership.clone(),
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
            call_controls: self.call_controls.clone(),
        }
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    pub(super) fn outbox(&mut self) -> Outbox<'_, ChatMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    /// Ids whose delivery state changed from inbound frames since the last
    /// drain — the runtime persists these rows.
    pub(super) fn take_dirty_outbound(&mut self) -> Vec<String> {
        std::mem::take(&mut self.dirty_outbound)
    }
}
