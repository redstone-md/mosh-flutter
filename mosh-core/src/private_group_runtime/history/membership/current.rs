use super::*;
use crate::sender_auth::SenderProof;

impl NativeCheckpoint {
    pub(in crate::private_group_runtime::history) fn reference(
        &self,
    ) -> Result<MembershipReference, PrivateGroupError> {
        Ok(MembershipReference::VerifiedSinceCheckpointV1(
            self.checkpoint.id()?,
        ))
    }

    pub(in crate::private_group_runtime::history) fn context(&self) -> &MlsHistoryContext {
        &self.checkpoint.context
    }

    pub(in crate::private_group_runtime::history) fn verify_current(
        &self,
        session: &mut GroupSession,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let proof: SenderProof = decode_json(&decode(&self.original_binding_proof_b64)?)?;
        let sender = session.verify_application(&proof, &self.binding_channel)?;
        if sender.peer_id != self.checkpoint.moss_key
            || hex::encode(&sender.mls_signer) != self.checkpoint.mls_key
        {
            return Err(PrivateGroupError::Codec(
                "current membership binding differs".into(),
            ));
        }
        Ok(sender)
    }

    pub(in crate::private_group_runtime::history) fn verify_at(
        &self,
        session: &GroupSession,
        at: &MlsHistoryContext,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        let context = &self.checkpoint;
        if context.conversation != session.deletions.context
            || context.mesh_id != session.mesh_id
            || (self.binding_channel != session.control_channel
                && self.binding_channel != session.data_channel)
        {
            return Err(PrivateGroupError::Codec(
                "membership checkpoint scope mismatch".into(),
            ));
        }
        let bytes = decode(&self.original_binding_proof_b64)?;
        if hex::encode(Sha256::digest(&bytes)) != context.binding_hash {
            return Err(PrivateGroupError::Codec(
                "membership checkpoint binding differs".into(),
            ));
        }
        let proof: SenderProof = decode_json(&bytes)?;
        let sender = proof
            .verify(&OrgContext {
                org_pubkey: session.org_pubkey.as_deref().unwrap_or(""),
                mesh_id: &session.mesh_id,
                channel_kind: &self.binding_channel,
            })
            .map_err(PrivateGroupError::Codec)?;
        if sender.peer_id != context.moss_key || hex::encode(&sender.mls_signer) != context.mls_key
        {
            return Err(PrivateGroupError::Codec(
                "membership checkpoint keys differ".into(),
            ));
        }
        session.continuous_membership(&context.context, at, &context.mls_key)?;
        Ok(sender)
    }
}
