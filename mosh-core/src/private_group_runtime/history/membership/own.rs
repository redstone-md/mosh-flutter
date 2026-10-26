use super::*;

impl GroupSession {
    pub(in crate::private_group_runtime::history) fn own_history_membership(
        &mut self,
    ) -> Result<NativeMembership, PrivateGroupError> {
        let context = self.crypto.history_context()?;
        let key = format!(
            "group/{}/local-own-membership/{}/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes())),
            hex::encode(self.crypto.signer_public()),
            self.device_fingerprint
        );
        let store = self
            .persistence
            .as_deref()
            .ok_or(PrivateGroupError::NotReady)?;
        if let Some(checkpoint) = store.group_history_evidence::<NativeCheckpoint>(&key)? {
            if self
                .continuous_membership(
                    checkpoint.context(),
                    &context,
                    &hex::encode(self.crypto.signer_public()),
                )
                .is_ok()
            {
                return Ok(NativeMembership {
                    reference: checkpoint.reference()?,
                    checkpoint,
                    writes: Vec::new(),
                });
            }
        }
        let request = ControlEnvelope::ResyncRequest {
            group_id: self.group_id.clone(),
            from_fingerprint: self.crypto.fingerprint(),
            have_epoch: self.crypto.epoch().ok_or(PrivateGroupError::NotReady)?,
        };
        let channel = self.control_channel.clone();
        // This existing scoped dual proof binds our own keys without sending
        // a ResyncRequest or depending circularly on a history Probe's ID.
        let proof = self.sign_application(&request, &channel)?;
        let bytes =
            serde_json::to_vec(&proof).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let sender = self.verify_application(&proof, &channel)?;
        let mut membership = self
            .native_membership_checkpoint(&sender, &bytes, &channel)?
            .ok_or_else(|| {
                PrivateGroupError::Codec("own membership evidence unavailable".into())
            })?;
        membership.writes.push(EvidenceWrite {
            key,
            bytes: serde_json::to_vec(&membership.checkpoint)
                .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        });
        Ok(membership)
    }
}
