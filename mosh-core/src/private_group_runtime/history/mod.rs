//! Native acceptance and recovery of retained, authenticated group history.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::{HistoryClassification, HistoryEvidence};
use crate::mls_crypto::StagedApplication;
use crate::persistence::HistoryAdmission;
use crate::sender_auth::VerifiedSender;

mod anchors;
mod evidence;
mod membership;
mod receipts;
mod transitions;
pub(super) use evidence::{native_acceptance_key, NativeAcceptance};
pub(super) use transitions::persist_membership;

impl GroupSession {
    pub(super) fn persist_received_text(
        &self,
        staged: &StagedApplication,
        message: &GroupMessage,
        original_proof: &[u8],
        sender: &VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let (mut accepted, mut evidence) =
            NativeAcceptance::text(self, message, sender, original_proof)?;
        let already_held = self.messages.holds_copy_of(message);
        evidence.extend(accepted.first_write(
            store,
            native_acceptance_key(
                &self.group_id,
                message.message_id.as_deref().unwrap_or_default(),
            ),
            already_held,
            &self.group_id,
        )?);
        let rows = if already_held {
            Vec::new()
        } else {
            vec![self.received_text_row(message, &accepted)?]
        };
        let record = serde_json::to_vec(&self.to_persisted_record())
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        store.commit_history_admission(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                org_authority: self.org_history_guard(&sender.peer_id, false)?,
                state: Some((&self.group_id, &record)),
                own_snapshot: Some(&staged.next.snapshot()),
                evidence: &evidence,
                ..Default::default()
            },
            &rows,
        )?;
        Ok(())
    }

    fn received_text_row(
        &self,
        message: &GroupMessage,
        accepted: &NativeAcceptance,
    ) -> Result<StoredMessage<GroupMessage>, PrivateGroupError> {
        let has_origin = message
            .metadata
            .as_ref()
            .is_some_and(|m| m.origin.is_some());
        Ok(StoredMessage {
            conversation_id: self.group_id.clone(),
            sent_at_ms: message.sent_at_ms.unwrap_or_default(),
            message_id: message.message_id.clone().unwrap_or_default(),
            message: message.clone(),
            attachment_manifest: None,
            preview_manifest: None,
            history_evidence: Some(HistoryEvidence {
                holder_key: self.device_fingerprint.clone(),
                classification: if has_origin {
                    HistoryClassification::OriginalOrigin
                } else {
                    HistoryClassification::LegacyUnsigned
                },
                legacy_original_id_absent: false,
                group: accepted.references()?,
            }),
        })
    }
}
