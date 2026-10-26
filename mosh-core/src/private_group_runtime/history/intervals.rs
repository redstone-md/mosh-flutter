//! Entitlement follows the receiver's protected own branch, never a claimed date.
use super::*;
use crate::mls_crypto::MlsHistoryContext;
use sha2::{Digest, Sha256};

impl GroupSession {
    /// Verify the complete local branch to our known head, then intersect the
    /// requested interval. A later removal does not invalidate earlier rows.
    pub(super) fn continuous_membership(
        &self,
        start: &MlsHistoryContext,
        at: &MlsHistoryContext,
        key: &str,
    ) -> Result<(), PrivateGroupError> {
        let head = self.crypto.history_context()?;
        if start.group_id != head.group_id
            || at.group_id != head.group_id
            || start.epoch > at.epoch
            || at.epoch > head.epoch
            || head.epoch.saturating_sub(start.epoch) > 4096
        {
            return Err(PrivateGroupError::Codec(
                "history membership interval unavailable".into(),
            ));
        }
        let store = self
            .persistence
            .as_deref()
            .ok_or(PrivateGroupError::NotReady)?;
        let mut cursor = start.clone();
        while cursor.epoch < head.epoch {
            let transition = store
                .group_history_evidence::<super::transitions::NativeTransition>(&format!(
                    "group/{}/transition/{:020}",
                    hex::encode(Sha256::digest(self.group_id.as_bytes())),
                    cursor.epoch
                ))?
                .ok_or(PrivateGroupError::NotReady)?;
            if transition.prior != cursor
                || transition.next.epoch != cursor.epoch + 1
                || transition.next.group_id != head.group_id
                || (cursor.epoch <= at.epoch
                    && !transition.previous_member_keys.iter().any(|k| k == key))
                || (transition.next.epoch <= at.epoch
                    && !transition.next_member_keys.iter().any(|k| k == key))
            {
                return Err(PrivateGroupError::Codec(
                    "history membership gap or branch differs".into(),
                ));
            }
            if cursor.epoch == at.epoch && cursor != *at {
                return Err(PrivateGroupError::Codec(
                    "historical context differs".into(),
                ));
            }
            cursor = transition.next;
        }
        if cursor != head
            || (at.epoch == head.epoch
                && (*at != head || !self.crypto.member_signers().iter().any(|k| k == key)))
        {
            return Err(PrivateGroupError::Codec(
                "known history head differs".into(),
            ));
        }
        Ok(())
    }
}
