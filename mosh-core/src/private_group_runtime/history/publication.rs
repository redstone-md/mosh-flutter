//! A successful native publish settles once with its protected original proof.
use super::*;
use crate::conversation::recovery::GroupAcceptanceBasis;
use crate::persistence::history_admission::EvidenceWrite;
use crate::persistence::PersistenceError;

pub(in crate::private_group_runtime) struct PublicationAcceptance {
    accepted: NativeAcceptance,
    membership: Vec<EvidenceWrite>,
}

impl GroupSession {
    /// Prepare the immutable facts before publication. They cannot be exported
    /// until the actual successful outcome enters the atomic send writer.
    pub(in crate::private_group_runtime) fn prepare_publication(
        &mut self,
        id: &str,
        original_proof: &[u8],
    ) -> Result<PublicationAcceptance, PrivateGroupError> {
        let proof = decode_json(original_proof)?;
        let sender = self.verify_application(&proof, &self.data_channel.clone())?;
        let message = self
            .messages
            .iter()
            .find(|m| m.message_id.as_deref() == Some(id))
            .cloned()
            .ok_or(PrivateGroupError::NotReady)?;
        let (mut accepted, membership) =
            NativeAcceptance::text(self, &message, &sender, original_proof)?;
        accepted.basis = GroupAcceptanceBasis::LocalPublication;
        accepted.receipt = None;
        accepted.receipt = super::receipts::AcceptanceEvidenceV1::native(self, &accepted)?;
        Ok(PublicationAcceptance {
            accepted,
            membership,
        })
    }

    pub(in crate::private_group_runtime) fn prepare_attachment_publication(
        &self,
        message: &GroupMessage,
        offer: AttachmentOffer,
        sender: &crate::sender_auth::VerifiedSender,
        original_proof: &[u8],
    ) -> Result<PublicationAcceptance, PrivateGroupError> {
        let (mut accepted, membership) =
            NativeAcceptance::attachment(self, message, sender, original_proof, offer)?;
        accepted.basis = GroupAcceptanceBasis::LocalPublication;
        accepted.receipt = None;
        accepted.receipt = super::receipts::AcceptanceEvidenceV1::native(self, &accepted)?;
        Ok(PublicationAcceptance {
            accepted,
            membership,
        })
    }

    pub(in crate::private_group_runtime) fn write_publication(
        &self,
        store: &Persistence,
        id: &str,
    ) -> Result<bool, PersistenceError> {
        let Some(publication) = self.publications.get(id) else {
            return Ok(false);
        };
        let mut accepted = publication.accepted.clone();
        let mut evidence = publication
            .membership
            .iter()
            .map(|e| EvidenceWrite {
                key: e.key.clone(),
                bytes: e.bytes.clone(),
            })
            .collect::<Vec<_>>();
        evidence.extend(
            accepted
                .first_write(
                    store,
                    native_acceptance_key(&self.group_id, id),
                    false,
                    &self.group_id,
                )
                .map_err(persistence_error)?,
        );
        let message = self
            .messages
            .iter()
            .find(|m| m.message_id.as_deref() == Some(id))
            .ok_or_else(|| PersistenceError::Json("published group row unavailable".into()))?;
        if message.delivery_status != Some(MessageDeliveryStatus::Sent)
            && publication.accepted.offer.is_none()
        {
            return Err(PersistenceError::Json(
                "publication outcome is not successful".into(),
            ));
        }
        let row = self
            .received_text_row(message, &accepted)
            .map_err(persistence_error)?;
        store.commit_history_admission(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                org_authority: self
                    .org_history_guard(&self.device_fingerprint, false)
                    .map_err(persistence_error)?,
                evidence: &evidence,
                outbound_settlements: &[id],
                ..Default::default()
            },
            &[row],
        )?;
        Ok(true)
    }
}

fn persistence_error(error: PrivateGroupError) -> PersistenceError {
    PersistenceError::Json(error.to_string())
}
