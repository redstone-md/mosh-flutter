//! The poll snapshot: the one shape the UI polls.

use super::*;

impl PrivateDmSession {
    pub(super) fn snapshot(&mut self) -> SessionSnapshot {
        // The poll is the heartbeat: a hint past its deadline stops being
        // carried (and files its lapse into the event ring) from here.
        self.expire_peer_typing(now_ms());
        let messages: Vec<ChatMessage> = self
            .messages
            .iter()
            .map(|message| {
                let mut stamped = message.clone();
                stamped.read = self.own_message_read(message);
                stamped
            })
            .collect();
        SessionSnapshot {
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            role: self.role.as_str().to_string(),
            display_name: self.device_id.clone(),
            peer_display_name: self.peer_display_name.clone().unwrap_or_default(),
            state: self.state,
            transport: self.reach(),
            peer_moss_id: self.peer_moss_id.clone(),
            last_connect_outcome: self.last_connect_outcome,
            invite_uri: self.invite_uri.clone(),
            fingerprint: self.fingerprint.clone(),
            messages,
            attachments: self.transfer.views(),
            mesh: self.mesh_info(),
            events: crate::conversation::mesh::snapshot_events(),
            pending_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Ringing {
                    Some(PendingCall {
                        call_id: call.call_id.clone(),
                        from_device: call.remote_device.clone(),
                    })
                } else {
                    None
                }
            }),
            outgoing_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Outgoing {
                    Some(OutgoingCall {
                        call_id: call.call_id.clone(),
                    })
                } else {
                    None
                }
            }),
            active_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Active {
                    Some(ActiveCall {
                        call_id: call.call_id.clone(),
                        direction: call.direction.as_str().to_string(),
                        key_b64: call.key_b64.clone(),
                        nonce_prefix_b64: call.nonce_prefix_b64.clone(),
                        started_at_ms: call.started_at_ms,
                    })
                } else {
                    None
                }
            }),
            peer_typing_until_ms: self.peer_typing_until_ms,
        }
    }

    pub(super) fn mesh_info(&self) -> Option<MeshInfo> {
        let mut info = self.transport.mesh_info()?;
        // The node is shared, so it reports every open conversation's channels.
        // This snapshot belongs to ONE of them: showing the others would put
        // another chat's session id in this chat's diagnostics panel. Peer
        // lists stay whole on purpose — `reach` matches the counterpart by id
        // against them.
        info.channels
            .retain(|channel| channel_session_id(channel) == Some(self.session_id.as_str()));
        Some(info)
    }

    /// What needs a live path right now: an attachment, a call. A text never
    /// asks; it queues.
    pub(super) fn ready_for_user_actions(&self) -> bool {
        self.state == DmSessionState::Connected
    }
}
