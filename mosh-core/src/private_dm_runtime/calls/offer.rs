use super::{protocol::CallControl, *};

impl PrivateDmSession {
    pub(super) fn receive_call_offer(
        &mut self,
        control: &CallControl,
        key: &str,
        nonce: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if decode(key)?.len() != 32 || decode(nonce)?.len() != 4 {
            return Err(PrivateDmRuntimeError::Codec(
                "invalid call media key".into(),
            ));
        }
        if self.closed_call_offer(&control.call_id)
            || self.call_occupancy.selected(&control.call_id)
        {
            return Ok(());
        }
        if let Some(call) = &self.call {
            if call.phase == CallPhase::Outgoing && call.call_id != control.call_id {
                return self.merge_cross_call(control, key, nonce);
            }
            if call.call_id == control.call_id
                && call.caller_signer == control.signer
                && matches!(call.phase, CallPhase::Accepting | CallPhase::Active)
            {
                return self.publish_call_accept(&control.call_id);
            }
            return Ok(());
        }
        if self.call_admission_blocked
            || self
                .call_occupancy
                .calls(now_ms())
                .iter()
                .any(|id| id != &control.call_id)
        {
            return self.publish_authenticated_call(
                &control.call_id,
                CallAction::Decline {
                    reason: "busy".into(),
                },
            );
        }
        self.install_incoming_call(control, key, nonce)?;
        Ok(())
    }

    fn closed_call_offer(&self, id: &str) -> bool {
        self.call_controls.closed(id)
            || self.messages.iter().any(|message| {
                message
                    .call_event
                    .as_ref()
                    .is_some_and(|event| event.call_id == id)
            })
    }

    fn merge_cross_call(
        &mut self,
        control: &CallControl,
        key: &str,
        nonce: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let call = self.call.as_ref().expect("outgoing call");
        if (&control.signer, &control.call_id) >= (&call.caller_signer, &call.call_id) {
            self.call.as_mut().expect("outgoing call").merged_call_id =
                Some(control.call_id.clone());
            return Ok(());
        }
        let old_id = call.call_id.clone();
        // Subscribe before replacing the working call. Failed setup keeps its slot.
        self.install_incoming_call(control, key, nonce)?;
        let call = self.call.as_mut().expect("incoming call");
        call.merged_call_id = Some(old_id.clone());
        call.phase = CallPhase::Accepting;
        call.mark_offer_sent(now_ms());
        let _ = self
            .transport
            .unsubscribe(&self.mesh_id, &voice_call_channel(&old_id));
        // An outgoing call already carries answer intent; failed publication is retried.
        self.publish_call_accept(&control.call_id)
    }

    fn install_incoming_call(
        &mut self,
        control: &CallControl,
        key: &str,
        nonce: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.transport
            .subscribe(&self.mesh_id, &voice_call_channel(&control.call_id))
            .map_err(PrivateDmRuntimeError::Moss)?;
        let mut call = CallState::ringing(
            control.call_id.clone(),
            key.into(),
            nonce.into(),
            control.name.clone(),
        );
        call.caller_signer = control.signer.clone();
        call.remote_peer = control.peer.clone();
        self.call = Some(call);
        self.note_authenticated_frame(&control.name);
        Ok(())
    }
}
