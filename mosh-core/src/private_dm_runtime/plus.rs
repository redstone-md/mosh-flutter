use super::*;

impl PrivateDmSession {
    pub(super) fn sync_plus(&mut self, now: u64) -> Result<(), PrivateDmRuntimeError> {
        if !self.peer_joined || !self.crypto.is_ready() || !self.plus_schedule.due(now) {
            return Ok(());
        }
        let Some(peer) = self.transport.local_peer_id() else {
            return Ok(());
        };
        let context = &self.deletions.context;
        let author = hex::encode(self.crypto.signer_public());
        let Some(frame) = crate::plus::global::frame(
            context,
            &peer,
            &author,
            |bytes| {
                self.crypto
                    .sign_sender_proof(bytes)
                    .map_err(|e| e.to_string())
            },
            now,
        )
        .map_err(PrivateDmRuntimeError::Codec)?
        else {
            return Ok(());
        };
        let frame = crate::plus::seal_mls(&self.crypto, context, &frame)
            .map_err(PrivateDmRuntimeError::Codec)?;
        let envelope = ControlEnvelope::PlusMetadata {
            session_id: self.session_id.clone(),
            frame,
        };
        let bytes = serde_json::to_vec(&envelope)
            .map_err(|e| PrivateDmRuntimeError::Codec(e.to_string()))?;
        self.route_send(ChannelKind::Control, &bytes)?;
        Ok(())
    }

    pub(super) fn receive_plus(
        &mut self,
        sealed: &crate::plus::SealedPlusFrame,
    ) -> Result<(), PrivateDmRuntimeError> {
        let context = &self.deletions.context;
        let frame = crate::plus::open_mls(&self.crypto, context, sealed)
            .map_err(PrivateDmRuntimeError::Codec)?;
        let membership = self
            .membership
            .as_ref()
            .ok_or_else(|| PrivateDmRuntimeError::Codec("PLUS peer identity unavailable".into()))?;
        if membership.call_own(&frame.author) {
            return Ok(());
        }
        let peer = membership
            .call_peer(&frame.author)
            .ok_or_else(|| PrivateDmRuntimeError::Codec("unknown PLUS peer".into()))?;
        if !self.crypto.member_signers().contains(&frame.author) {
            return Err(PrivateDmRuntimeError::Codec(
                "PLUS peer is not authorized".into(),
            ));
        }
        let account = crate::message_deletion::ownership::verify(&frame.ownership, &frame.author)
            .map_err(PrivateDmRuntimeError::Codec)?;
        if membership.deletion_accounts().get(&frame.author) != Some(&account) {
            return Err(PrivateDmRuntimeError::Codec(
                "PLUS peer account mismatch".into(),
            ));
        }
        let aliases = [context.clone(), format!("{context}:{peer}"), peer];
        crate::plus::global::accept(&frame, context, &frame.author, &aliases, now_ms())
            .map_err(PrivateDmRuntimeError::Codec)
    }
}
