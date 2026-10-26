//! History restores the original offer, leaving file downloads under user control.
use super::*;
use crate::conversation::attachments::AttachmentDirection;

impl GroupSession {
    pub(in crate::private_group_runtime) fn attachment_history_message(
        &self,
        from_device: String,
        from_fingerprint: String,
        offer: &AttachmentOffer,
        sent_at_ms: Option<u64>,
    ) -> GroupMessage {
        self.messages.stamp(GroupMessage {
            metadata: offer.manifest.origin.clone().map(|origin| {
                crate::message_deletion::MessageMetadata {
                    origin: Some(origin),
                    is_own: Some(from_fingerprint == self.device_fingerprint),
                    ..Default::default()
                }
            }),
            from_device,
            from_fingerprint,
            body: String::new(),
            message_id: offer.manifest.origin.as_ref().map(|o| o.id.clone()),
            sent_at_ms,
            attachment: Some(crate::conversation::attachments::descriptor_of(
                &offer.manifest,
            )),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            name_change: None,
        })
    }

    pub(in crate::private_group_runtime) fn persist_provisional_offer(
        &self,
        message: &GroupMessage,
        offer: &AttachmentOffer,
    ) -> Result<(), PrivateGroupError> {
        let Some(store) = self.persistence.as_deref() else {
            return Ok(());
        };
        let mut pending = message.clone();
        pending.delivery_status = Some(MessageDeliveryStatus::Pending);
        let row = StoredMessage {
            conversation_id: self.group_id.clone(),
            message_id: pending.message_id.clone().unwrap_or_default(),
            sent_at_ms: pending.sent_at_ms.unwrap_or_default(),
            message: pending,
            attachment_manifest: Some(offer.manifest.clone()),
            preview_manifest: offer.preview_manifest.clone(),
            history_evidence: None,
        };
        store.commit_history_admission(
            GROUP_HISTORY,
            &self.group_id,
            HistoryAdmission {
                own_snapshot: Some(&self.crypto.snapshot()),
                ..Default::default()
            },
            &[row],
        )?;
        Ok(())
    }

    pub(super) fn restore_history_offer(&mut self, row: &StoredMessage<GroupMessage>) {
        if let Some(descriptor) = &row.message.attachment {
            self.transfer.restore_stored(
                descriptor,
                AttachmentDirection::Incoming,
                row.attachment_manifest.clone(),
            );
        }
    }
}
