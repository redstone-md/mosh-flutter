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
    pub(super) fn publish_control(&self, value: &ControlEnvelope) -> Result<(), PrivateGroupError> {
        if value.is_application() {
            let proof = self.sign_application(value, &self.control_channel)?;
            return publish_control_message(
                &self.node,
                &self.control_channel,
                &self.mesh_id,
                org_context(self.org_pubkey.as_deref(), self.org_signer.as_ref()),
                &proof,
            );
        }
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
        let Ok(ciphertext_b64) = self.crypto.encrypt_json(&body) else {
            return;
        };
        let envelope = ControlEnvelope::TypingIndicator {
            group_id: self.group_id.clone(),
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            typing_ciphertext_b64: ciphertext_b64,
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

pub(super) fn channel_group_id(channel: &str) -> Option<&str> {
    channel
        .strip_prefix(CONTROL_CHANNEL_PREFIX)
        .or_else(|| channel.strip_prefix(DATA_CHANNEL_PREFIX))
        .or_else(|| channel.strip_prefix(BLOB_CHANNEL_PREFIX))
}

pub(super) fn group_channels(group_id: &str) -> [String; 3] {
    [
        format!("{CONTROL_CHANNEL_PREFIX}{group_id}"),
        format!("{DATA_CHANNEL_PREFIX}{group_id}"),
        format!("{BLOB_CHANNEL_PREFIX}{group_id}"),
    ]
}

/// Always room-scoped: the shared node's own room is the substrate, so a
/// room-less publish would land where none of this group's peers listen.
///
/// Best-effort: this carries control and blob frames, which report no delivery
/// status of their own, so an empty group is not a failure to hand back. A
/// user message does not come through here — it publishes directly in
/// `publish_prepared`, where "no peers" does fail the send.
pub(super) fn publish_json<T: Serialize>(
    node: &MossNode,
    mesh_id: &str,
    channel: &str,
    value: &T,
) -> Result<(), PrivateGroupError> {
    let payload =
        serde_json::to_vec(value).map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
    node.publish_room_best_effort(mesh_id, channel, &payload)
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))
}

pub(super) fn org_context<'a>(
    org_pubkey: Option<&'a str>,
    org_signer: Option<&'a SigningKey>,
) -> Option<(&'a str, &'a SigningKey)> {
    org_pubkey.zip(org_signer)
}

/// Publish on a group control channel: wrapped in the org signed envelope
/// when an org binding is present, raw JSON otherwise (ADR 0007).
pub(super) fn publish_control_message<T: Serialize>(
    node: &MossNode,
    control_channel: &str,
    mesh_id: &str,
    org: Option<(&str, &SigningKey)>,
    value: &T,
) -> Result<(), PrivateGroupError> {
    match org {
        Some((org_pubkey, signer)) => {
            let payload = serde_json::to_vec(value)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
            let ctx = OrgContext {
                org_pubkey,
                mesh_id,
                channel_kind: control_channel,
            };
            let env = org_envelope::sign(signer, &ctx, &payload);
            publish_json(node, mesh_id, control_channel, &env)
        }
        None => publish_json(node, mesh_id, control_channel, value),
    }
}

/// The node identity key doubles as the org control-channel signer. Its
/// absence is an error, not a downgrade: an org group must never fall back
/// to unauthenticated control traffic.
pub(super) fn load_org_signer(
    persistence: Option<&Persistence>,
) -> Result<SigningKey, PrivateGroupError> {
    let blob = persistence
        .ok_or_else(|| PrivateGroupError::Moss("org group requires persistence".to_string()))?
        .get_moss_identity()
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))?
        .ok_or_else(|| PrivateGroupError::Moss("moss identity unavailable".to_string()))?;
    org_signing::signing_key_from_identity(&blob)
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))
}

pub(super) fn decode_json<T: for<'de> Deserialize<'de>>(
    bytes: &[u8],
) -> Result<T, PrivateGroupError> {
    serde_json::from_slice(bytes).map_err(|error| PrivateGroupError::Codec(error.to_string()))
}
