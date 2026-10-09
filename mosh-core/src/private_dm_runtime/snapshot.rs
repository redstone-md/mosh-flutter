//! The poll snapshot: the one shape the UI polls.

use super::*;

impl PrivateDmSession {
    pub(super) fn snapshot(&mut self) -> SessionSnapshot {
        // The poll is the heartbeat: a hint past its deadline stops being
        // carried (and files its lapse into the event ring) from here.
        self.expire_peer_typing(now_ms());
        let authority = self.deletion_authority().ok();
        let mut messages: Vec<ChatMessage> = crate::message_deletion::snapshot::messages(
            &self.messages,
            &self.transfer,
            &self.deletions,
            authority.as_ref(),
        )
        .iter()
        .map(|message| {
            let mut stamped = message.clone();
            stamped.read = self.own_message_read(message);
            stamped
        })
        .collect();
        let history_sync = self.history_sync_state(now_ms());
        if history_sync.is_some() {
            messages
                .sort_by(|a, b| (a.sent_at_ms, &a.message_id).cmp(&(b.sent_at_ms, &b.message_id)));
        }
        SessionSnapshot {
            call_availability: None,
            deletion_summary: self.deletions.summary(),
            device_revocation: self.device_revocation_state(),
            history_sync,
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
            invite_available: self.invite_available(),
            fingerprint: self.fingerprint.clone(),
            messages,
            attachments: self.transfer.views(),
            mesh: self.mesh_info(),
            events: crate::conversation::mesh::snapshot_events(),
            pending_call: self.call.as_ref().and_then(|call| {
                if matches!(call.phase, CallPhase::Ringing | CallPhase::Accepting) {
                    Some(PendingCall {
                        call_id: call.call_id.clone(),
                        superseded_call_id: call.presentation_alias(),
                        from_device: call.remote_device.clone(),
                        answer_pending: call.phase == CallPhase::Accepting,
                    })
                } else {
                    None
                }
            }),
            outgoing_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Outgoing {
                    Some(OutgoingCall {
                        call_id: call.call_id.clone(),
                        superseded_call_id: call.presentation_alias(),
                    })
                } else {
                    None
                }
            }),
            active_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Active {
                    Some(ActiveCall {
                        call_id: call.call_id.clone(),
                        superseded_call_id: call.presentation_alias(),
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
