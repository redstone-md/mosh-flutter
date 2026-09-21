//! Publishing and the typing signal.

use super::*;

impl GroupSession {
    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    pub(super) fn outbox(&mut self) -> Outbox<'_, GroupMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    pub(super) fn to_persisted_record(&self) -> PersistedGroupSession {
        PersistedGroupSession {
            group_id: self.group_id.clone(),
            mesh_id: self.mesh_id.clone(),
            label: self.label.clone(),
            display_name: self.display_name.clone(),
            participant_id: self.participant_id.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            creator_fingerprint: self.creator_fingerprint.clone(),
            current_admin_fingerprint: self.current_admin_fingerprint.clone(),
            is_admin: self.is_admin,
            invite_uri: self.invite_uri.clone(),
            joined: self.joined,
            signer_public: self.crypto.signer_public(),
            mls_group_id: self.crypto.group_id_bytes().unwrap_or_default(),
            listen_port: self.listen_port,
            static_peer: self.static_peer.clone(),
            org_pubkey: self.org_pubkey.clone(),
        }
    }

    /// Control-channel publish. Org groups wrap every frame in the signed
    /// envelope (ADR 0007) — including resync traffic, closing the
    /// unauthenticated-resync residual from the plain-group path.
    pub(super) fn publish_control<T: Serialize>(&self, value: &T) -> Result<(), PrivateGroupError> {
        publish_control_message(
            &self.node,
            &self.control_channel,
            &self.mesh_id,
            org_context(self.org_pubkey.as_deref(), self.org_signer.as_ref()),
            value,
        )
    }

    /// Publishes a typing hint if the refresh cadence allows one. Same shape
    /// as the DM hint: the composer calls on every keystroke, the runtime
    /// folds it down, and the receiver owns the expiry. A hint the transport
    /// refuses is simply retried on the next call.
    pub(super) fn publish_typing(&mut self, now: u64) {
        if !self.joined || !self.crypto.is_ready() {
            return;
        }
        if !self.typing_gate.send_due(now) {
            return;
        }
        let body = GroupTypingBody {
            device: self.display_name.clone(),
            until_ms: TypingGate::deadline(now),
        };
        let Ok(body_json) = serde_json::to_vec(&body) else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(&body_json) else {
            return;
        };
        let envelope = ControlEnvelope::TypingIndicator {
            group_id: self.group_id.clone(),
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            typing_ciphertext_b64: encode(&ciphertext),
        };
        let _ = self.publish_control(&envelope);
    }

    /// A decrypted hint from a member: stamp that member's deadline from OUR
    /// clock (the sender's `until_ms` stays advisory), learn their display
    /// name from the authenticated `from_device`, and file the event when
    /// the member's hint is new (a refresh must not spam the ring).
    pub(super) fn note_member_typing(&mut self, fingerprint: String, from_device: &str, now: u64) {
        self.member_names
            .entry(fingerprint.clone())
            .or_insert_with(|| from_device.to_string());
        let fresh = !matches!(self.typing_members.get(&fingerprint), Some(until) if *until > now);
        self.typing_members
            .insert(fingerprint, TypingGate::deadline(now));
        if fresh {
            typing_shared::push_typing_event(&self.group_id, "started");
        }
    }

    /// A member's inbound message contradicts "typing": that member's hint
    /// dies at once, whatever its deadline said.
    pub(super) fn clear_member_typing(&mut self, fingerprint: &str) {
        if self.typing_members.remove(fingerprint).is_some() {
            typing_shared::push_typing_event(&self.group_id, "stopped");
        }
    }
}
