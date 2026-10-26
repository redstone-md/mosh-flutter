use super::*;
use super::{
    membership::MembershipReference,
    protocol::{CurrentHead, GroupScope},
};
use ed25519_dalek::Signer as _;

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct HolderVouchV1 {
    version: u8,
    conversation: String,
    mesh_id: String,
    org_pubkey: Option<String>,
    record_hash: String,
    acceptance_evidence_hash: String,
    historical_context: crate::mls_crypto::MlsHistoryContext,
    author_admission_instance: MembershipReference,
    recipient_mls_key: String,
    recipient_moss_key: String,
    recipient_current_admission: MembershipReference,
    recipient_entitled_admission: MembershipReference,
    holder_current_head: CurrentHead,
    holder_mls_key: String,
    holder_moss_key: String,
    mls_signature: String,
    moss_signature: String,
}

impl HolderVouchV1 {
    pub(super) fn issue(
        session: &mut GroupSession,
        accepted: &NativeAcceptance,
        recipient: &GroupScope,
        peer: &str,
    ) -> Result<Self, PrivateGroupError> {
        let member = session.validate_history_scope(recipient, peer)?;
        recipient.membership.verify_at(session, &accepted.context)?;
        let receipt = accepted
            .receipt
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let instance = recipient.membership.reference()?;
        let mut vouch = Self {
            version: 1,
            conversation: session.deletions.context.clone(),
            mesh_id: session.mesh_id.clone(),
            org_pubkey: session.org_pubkey.clone(),
            record_hash: accepted.record_hash.clone(),
            acceptance_evidence_hash: receipt.hash()?,
            historical_context: accepted.context.clone(),
            author_admission_instance: accepted
                .author_admission_instance
                .clone()
                .ok_or(PrivateGroupError::NotReady)?,
            recipient_mls_key: hex::encode(member.mls_signer),
            recipient_moss_key: member.peer_id,
            recipient_current_admission: instance.clone(),
            recipient_entitled_admission: instance,
            holder_current_head: session.current_history_head()?,
            holder_mls_key: hex::encode(session.crypto.signer_public()),
            holder_moss_key: session.device_fingerprint.clone(),
            mls_signature: String::new(),
            moss_signature: String::new(),
        };
        let input = vouch.input()?;
        vouch.mls_signature = hex::encode(session.crypto.sign_sender_proof(&input)?);
        vouch.moss_signature = hex::encode(
            session
                .node
                .identity_signer()
                .map_err(|e| PrivateGroupError::Moss(e.to_string()))?
                .sign(&input)
                .to_bytes(),
        );
        Ok(vouch)
    }

    pub(super) fn verify(
        &self,
        session: &mut GroupSession,
        accepted: &NativeAcceptance,
        holder: &crate::sender_auth::VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let own = session.own_history_scope()?;
        if self.version != 1
            || self.conversation != session.deletions.context
            || self.mesh_id != session.mesh_id
            || self.org_pubkey != session.org_pubkey
            || self.record_hash != accepted.record_hash
            || self.historical_context != accepted.context
            || self.holder_current_head != session.current_history_head()?
            || self.holder_mls_key != hex::encode(&holder.mls_signer)
            || self.holder_moss_key != holder.peer_id
            || self.recipient_mls_key != hex::encode(session.crypto.signer_public())
            || self.recipient_moss_key != session.device_fingerprint
            || self.recipient_current_admission != own.membership.reference()?
            || self.recipient_entitled_admission != own.membership.reference()?
            || Some(&self.author_admission_instance) != accepted.author_admission_instance.as_ref()
            || self.acceptance_evidence_hash
                != accepted
                    .receipt
                    .as_ref()
                    .ok_or(PrivateGroupError::NotReady)?
                    .hash()?
        {
            return Err(PrivateGroupError::Codec(
                "holder vouch entitlement differs".into(),
            ));
        }
        own.membership
            .verify_at(session, &self.historical_context)?;
        let input = self.input()?;
        crate::signature_verification::verify(&self.holder_mls_key, &self.mls_signature, &input)
            .map_err(PrivateGroupError::Codec)?;
        crate::signature_verification::verify(&self.holder_moss_key, &self.moss_signature, &input)
            .map_err(PrivateGroupError::Codec)
    }

    fn input(&self) -> Result<Vec<u8>, PrivateGroupError> {
        let mut input = b"mosh-history-holder-vouch-v1\0".to_vec();
        input.extend(
            serde_json::to_vec(&(
                self.version,
                &self.conversation,
                &self.mesh_id,
                &self.org_pubkey,
                &self.record_hash,
                &self.acceptance_evidence_hash,
                (self.historical_context.epoch, &self.historical_context.hash),
                self.author_admission_instance.tuple(),
                &self.recipient_mls_key,
                &self.recipient_moss_key,
                self.recipient_current_admission.tuple(),
                self.recipient_entitled_admission.tuple(),
                (
                    self.holder_current_head.context.epoch,
                    &self.holder_current_head.context.hash,
                    self.holder_current_head.org_roster_version,
                    &self.holder_current_head.org_roster_hash,
                ),
                &self.holder_mls_key,
                &self.holder_moss_key,
            ))
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        );
        Ok(input)
    }
}
