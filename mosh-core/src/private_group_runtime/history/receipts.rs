//! Separate holder receipts preserve original authorship and native provenance.
use super::membership::MembershipReference;
use super::*;
use crate::conversation::recovery::{GroupAcceptanceBasis, GroupHistoryReferences};
use crate::mls_crypto::MlsHistoryContext;
use ed25519_dalek::Signer as _;
use sha2::{Digest, Sha256};

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct AcceptanceEvidenceV1 {
    version: u8,
    evidence_id: String,
    record_hash: String,
    original_origin_hash: String,
    historical_context: MlsHistoryContext,
    author_admission_instance: MembershipReference,
    holder_mls_key: String,
    holder_moss_key: String,
    accepted_head: MlsHistoryContext,
    basis: GroupAcceptanceBasis,
    first_evidence_hash: Option<String>,
    predecessor_hash: Option<String>,
    mls_signature: String,
    moss_signature: String,
}

impl AcceptanceEvidenceV1 {
    pub(super) fn native(
        session: &GroupSession,
        accepted: &NativeAcceptance,
    ) -> Result<Option<Self>, PrivateGroupError> {
        let (Some(admission), Some(origin)) =
            (&accepted.author_admission_instance, &accepted.origin)
        else {
            return Ok(None);
        };
        let mut receipt = Self {
            version: 1,
            evidence_id: hex::encode(rand::random::<[u8; 16]>()),
            record_hash: accepted.record_hash.clone(),
            original_origin_hash: crate::conversation::recovery::manifest::digest(origin)
                .map_err(PrivateGroupError::Codec)?,
            historical_context: accepted.context.clone(),
            author_admission_instance: admission.clone(),
            holder_mls_key: hex::encode(session.crypto.signer_public()),
            holder_moss_key: session.device_fingerprint.clone(),
            accepted_head: accepted.context.clone(),
            basis: accepted.basis,
            first_evidence_hash: accepted
                .receipt
                .as_ref()
                .map(|previous| {
                    previous
                        .first_evidence_hash
                        .clone()
                        .map(Ok)
                        .unwrap_or_else(|| previous.hash())
                })
                .transpose()?,
            predecessor_hash: accepted.receipt.as_ref().map(Self::hash).transpose()?,
            mls_signature: String::new(),
            moss_signature: String::new(),
        };
        let input = receipt.input()?;
        receipt.mls_signature = hex::encode(session.crypto.sign_sender_proof(&input)?);
        receipt.moss_signature = hex::encode(
            session
                .node
                .identity_signer()
                .map_err(|e| PrivateGroupError::Moss(e.to_string()))?
                .sign(&input)
                .to_bytes(),
        );
        Ok(Some(receipt))
    }

    fn input(&self) -> Result<Vec<u8>, PrivateGroupError> {
        let mut input = b"mosh-history-acceptance-v1\0".to_vec();
        input.extend(
            serde_json::to_vec(&(
                self.version,
                &self.evidence_id,
                &self.record_hash,
                &self.original_origin_hash,
                (self.historical_context.epoch, &self.historical_context.hash),
                self.author_admission_instance.tuple(),
                &self.holder_mls_key,
                &self.holder_moss_key,
                (self.accepted_head.epoch, &self.accepted_head.hash),
                self.basis,
                &self.first_evidence_hash,
                &self.predecessor_hash,
            ))
            .map_err(|e| PrivateGroupError::Codec(e.to_string()))?,
        );
        Ok(input)
    }

    pub(super) fn verify(&self, accepted: &NativeAcceptance) -> Result<(), PrivateGroupError> {
        let origin = accepted
            .origin
            .as_ref()
            .ok_or_else(|| PrivateGroupError::Codec("original origin unavailable".into()))?;
        if self.version != 1
            || !crate::conversation::recovery::manifest::canonical_hex(&self.evidence_id, 32)
            || self.record_hash != accepted.record_hash
            || self.original_origin_hash
                != crate::conversation::recovery::manifest::digest(origin)
                    .map_err(PrivateGroupError::Codec)?
            || self.historical_context != accepted.context
            || Some(&self.author_admission_instance) != accepted.author_admission_instance.as_ref()
            || self.accepted_head.group_id != self.historical_context.group_id
            || self.accepted_head.epoch < self.historical_context.epoch
            || (self.accepted_head.epoch == self.historical_context.epoch
                && self.accepted_head.hash != self.historical_context.hash)
        {
            return Err(PrivateGroupError::Codec(
                "acceptance evidence binding differs".into(),
            ));
        }
        let input = self.input()?;
        crate::signature_verification::verify(&self.holder_mls_key, &self.mls_signature, &input)
            .map_err(PrivateGroupError::Codec)?;
        crate::signature_verification::verify(&self.holder_moss_key, &self.moss_signature, &input)
            .map_err(PrivateGroupError::Codec)
    }

    pub(super) fn hash(&self) -> Result<String, PrivateGroupError> {
        crate::conversation::recovery::manifest::digest(self).map_err(PrivateGroupError::Codec)
    }
}

impl NativeAcceptance {
    pub(super) fn references(&self) -> Result<Option<GroupHistoryReferences>, PrivateGroupError> {
        self.receipt
            .as_ref()
            .map(|receipt| {
                Ok(GroupHistoryReferences {
                    original_sender_proof_hash: hex::encode(Sha256::digest(decode(
                        &self.original_sender_proof_b64,
                    )?)),
                    content_proof_hash: None,
                    acceptance_evidence_hash: receipt.hash()?,
                    first_evidence_hash: receipt.first_evidence_hash.clone(),
                    predecessor_hash: receipt.predecessor_hash.clone(),
                    basis: receipt.basis,
                })
            })
            .transpose()
    }
}
