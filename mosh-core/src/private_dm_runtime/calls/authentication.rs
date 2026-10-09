use super::{protocol::CallControl, *};

impl PrivateDmSession {
    pub(super) fn publish_authenticated_call(
        &mut self,
        call_id: &str,
        action: protocol::CallAction,
    ) -> Result<(), PrivateDmRuntimeError> {
        let control = CallControl {
            session_id: self.session_id.clone(),
            call_id: call_id.into(),
            signer: hex::encode(self.crypto.signer_public()),
            sequence: self
                .call_controls
                .allocate_sequence()
                .ok_or(PrivateDmRuntimeError::NotReady)?,
            peer: self
                .transport
                .local_peer_id()
                .ok_or(PrivateDmRuntimeError::NotReady)?,
            name: self.device_id.clone(),
            action,
        };
        let ciphertext_b64 = self.crypto.encrypt_json(&control)?;
        self.record_dirty = true;
        self.persist_device_crypto()?;
        self.send_call_control(&ControlEnvelope::CallControl {
            session_id: self.session_id.clone(),
            ciphertext_b64,
        })
    }

    pub(super) fn decrypt_call_control(
        &mut self,
        ciphertext_b64: &str,
    ) -> Result<CallControl, PrivateDmRuntimeError> {
        if let Some(membership) = &self.membership {
            self.call_controls
                .retain_signers(|signer| membership.call_peer(signer).is_some());
        }
        let ciphertext = decode(ciphertext_b64)?;
        let membership = self.membership.as_ref();
        let own = hex::encode(self.crypto.signer_public());
        let peer = self.peer_moss_id.as_deref();
        let session_id = &self.session_id;
        let (body, _) = self.crypto.decrypt_checked(&ciphertext, |body, signer| {
            let control: CallControl = serde_json::from_slice(body).map_err(|e| e.to_string())?;
            if control.session_id != *session_id
                || control.signer != hex::encode(signer)
                || control.call_id.is_empty()
                || control.call_id.len() > 128
                || control.name.len() > 256
                || control.sequence == 0
            {
                return Err("invalid authenticated call control".into());
            }
            match membership {
                Some(membership)
                    if membership.call_peer(&control.signer).as_deref() == Some(&control.peer)
                        && control.admitted_participants(membership) =>
                {
                    Ok(())
                }
                None if control.signer != own && peer == Some(control.peer.as_str()) => Ok(()),
                _ => Err("call device is not an admitted participant".into()),
            }
        })?;
        self.persist_device_crypto()?;
        decode_json(&body)
    }
}

impl CallControl {
    fn admitted_participants(
        &self,
        membership: &crate::private_dm_runtime::devices::DeviceMembership,
    ) -> bool {
        let admitted = |signer: &str| membership.call_peer(signer).is_some();
        match &self.action {
            CallAction::Selected { receiver } => {
                admitted(receiver)
                    && membership.call_own(receiver) != membership.call_own(&self.signer)
            }
            CallAction::Occupied { caller, receiver } => {
                admitted(caller)
                    && receiver
                        .as_ref()
                        .is_none_or(|receiver| receiver == &self.signer)
            }
            CallAction::End { caller, .. } => admitted(caller),
            _ => true,
        }
    }
}
