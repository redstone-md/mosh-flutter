//! Unknown current leaves may carry only bounded evidence, never historical content.
use super::{protocol::GroupBody, transition_exchange::EvidenceMessage, *};
use crate::conversation::recovery::wire::HistoryMessage;
use crate::mls_crypto::MlsHistoryContext;
use crate::sender_auth::VerifiedSender;
use sha2::{Digest, Sha256};

impl GroupSession {
    pub(super) fn history_carrier_member(
        &mut self,
        body: &GroupBody,
    ) -> Result<VerifiedSender, PrivateGroupError> {
        match body.scope.membership.verify_current(self) {
            Ok(sender) => Ok(sender),
            Err(error) => {
                let have = self.crypto.history_context()?;
                let remote = &body.scope.head.context;
                let only_evidence = matches!(
                    (&body.message, &body.evidence),
                    (HistoryMessage::Probe, None)
                        | (
                            HistoryMessage::Unavailable,
                            Some(EvidenceMessage::Page { .. })
                        )
                );
                if !only_evidence
                    || remote.group_id != have.group_id
                    || remote.epoch <= have.epoch
                    || remote.epoch - have.epoch > 4096
                {
                    return Err(error);
                }
                let sender = body.scope.membership.verify_binding(self)?;
                if self.org_pubkey.is_some() && !self.roster_contains(&sender.peer_id) {
                    return Err(error);
                }
                Ok(sender)
            }
        }
    }

    pub(super) fn retained_transition(
        &self,
        have: &MlsHistoryContext,
    ) -> Result<super::transitions::NativeTransition, PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let prefix = format!(
            "group/{}",
            hex::encode(Sha256::digest(self.group_id.as_bytes()))
        );
        if let Some(transition) = store
            .group_history_evidence::<super::transitions::NativeTransition>(&format!(
                "{prefix}/transition/{:020}",
                have.epoch
            ))?
            .filter(|transition| transition.prior == *have)
        {
            return Ok(transition);
        }
        for anchor in store.group_evidence_page::<super::anchors::NativeAdmissionAnchor>(
            &format!("{prefix}/evidence/admission-anchor/"),
        )? {
            if let Some(transition) =
                anchor.transition_for(have, self.org_pubkey.as_deref(), &self.mesh_id)?
            {
                return Ok(transition);
            }
        }
        Err(PrivateGroupError::NotReady)
    }
}

#[cfg(test)]
#[path = "bootstrap_tests.rs"]
mod tests;
