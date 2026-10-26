//! Native acceptance and recovery of retained, authenticated group history.
use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::{HistoryClassification, HistoryEvidence};
use crate::mls_crypto::StagedApplication;
use crate::persistence::HistoryAdmission;
use crate::sender_auth::VerifiedSender;

pub(super) mod admission;
mod admission_commit;
mod anchors;
mod attachments;
mod evidence;
mod exchange;
mod import;
mod ingress;
mod install;
mod intervals;
mod journal;
mod membership;
mod original;
mod protocol;
mod publication;
pub(super) use publication::PublicationAcceptance;
mod receipts;
mod records;
mod recovery;
mod source;
mod source_pages;
mod transitions;
mod vouches;
pub(super) use evidence::{native_acceptance_key, NativeAcceptance};
pub(super) use protocol::CurrentHead;
pub(super) use transitions::persist_membership;

impl GroupSession {
    pub(super) fn persist_received_text(
        &self,
        staged: &StagedApplication,
        message: &GroupMessage,
        original_proof: &[u8],
        sender: &VerifiedSender,
    ) -> Result<(), PrivateGroupError> {
        if self.persistence.is_none() {
            return Ok(());
        }
        let (accepted, evidence) = NativeAcceptance::text(self, message, sender, original_proof)?;
        self.persist_received(staged, message, accepted, evidence)
    }

    pub(super) fn persist_received(
        &self,
        staged: &StagedApplication,
        message: &GroupMessage,
        mut accepted: NativeAcceptance,
        mut evidence: Vec<crate::persistence::history_admission::EvidenceWrite>,
    ) -> Result<(), PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let sender = accepted.original_author_moss_key.clone();
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
        let background = rows
            .iter()
            .filter_map(|row| {
                crate::conversation::history::background::message(
                    GROUP_HISTORY,
                    &self.group_id,
                    row.sent_at_ms,
                    &row.message_id,
                    &row.message,
                )
            })
            .collect::<Vec<_>>();
        store.commit_history_admission(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                org_authority: self.org_history_guard(&sender, false)?,
                state: Some((&self.group_id, &record)),
                own_snapshot: Some(&staged.next.snapshot()),
                evidence: &evidence,
                background_messages: &background,
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
            attachment_manifest: accepted.offer.as_ref().map(|o| o.manifest.clone()),
            preview_manifest: accepted
                .offer
                .as_ref()
                .and_then(|o| o.preview_manifest.clone()),
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
