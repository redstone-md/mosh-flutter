//! Rejoin rights require the same current Moss key and retained original MLS binding.
use super::*;
use super::{membership::NativeCheckpoint, protocol::GroupScope};
use crate::mls_crypto::MlsHistoryContext;
use sha2::{Digest, Sha256};

impl GroupSession {
    pub(super) fn previous_history_memberships(
        &self,
        current: &NativeCheckpoint,
    ) -> Result<Vec<NativeCheckpoint>, PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let all = store.group_evidence_page::<NativeCheckpoint>(&format!(
            "group/{}/local-own-membership/",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        ))?;
        let mut old = Vec::new();
        for checkpoint in all {
            if checkpoint.moss_key() == self.device_fingerprint
                && checkpoint.reference()? != current.reference()?
            {
                old.push(checkpoint);
            }
        }
        old.sort_by_key(|checkpoint| checkpoint.context().epoch);
        Ok(old)
    }
}

impl GroupScope {
    pub(super) fn entitled_at(
        &self,
        session: &GroupSession,
        at: &MlsHistoryContext,
    ) -> Result<Option<&NativeCheckpoint>, PrivateGroupError> {
        if self.previous_memberships.len() > 32 {
            return Err(PrivateGroupError::Codec("too many group intervals".into()));
        }
        let mut missing = false;
        for checkpoint in
            std::iter::once(&self.membership).chain(self.previous_memberships.iter().rev())
        {
            if checkpoint.moss_key() != self.membership.moss_key() {
                return Err(PrivateGroupError::Codec(
                    "rejoin Moss binding differs".into(),
                ));
            }
            if checkpoint.excludes_before_admission(at) {
                continue;
            }
            if checkpoint.verify_at(session, at).is_ok() {
                return Ok(Some(checkpoint));
            }
            missing |= session.known_member_at(at, checkpoint.mls_key())? != Some(false);
        }
        // Only a known canonical admission can prove prejoin exclusion.
        if !missing {
            return Ok(None);
        }
        Err(PrivateGroupError::Codec(
            "recipient history interval unavailable".into(),
        ))
    }
}
