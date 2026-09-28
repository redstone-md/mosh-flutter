//! A sibling receipt ends its retry without claiming delivery to the contact.
use super::super::*;
use super::{invalid, types::Result};

impl PrivateDmSession {
    pub(in crate::private_dm_runtime) fn track_device_receipts(&mut self, message: &str) {
        if !self.devices_live() {
            return;
        }
        let own = hex::encode(self.crypto.signer_public());
        if let Some(membership) = &mut self.membership {
            membership
                .receipt_targets
                .entry(message.into())
                .or_insert_with(|| {
                    membership
                        .topology
                        .clients
                        .iter()
                        .filter(|client| client.mls_signer != own)
                        .map(|client| client.mls_signer.clone())
                        .collect()
                });
        }
    }

    pub(in crate::private_dm_runtime) fn accept_device_receipt(
        &mut self,
        id: &str,
        signer: &[u8],
    ) -> Result<()> {
        let (_, own) = self.device_author(signer)?;
        let membership = self.membership.as_mut().ok_or_else(invalid)?;
        if !own && !membership.delivered_ids.iter().any(|seen| seen == id) {
            membership.delivered_ids.push(id.into());
            let overflow = membership
                .delivered_ids
                .len()
                .saturating_sub(READ_HISTORY_KEEP);
            membership.delivered_ids.drain(..overflow);
        }
        let signer = hex::encode(signer);
        if let Some(targets) = membership.receipt_targets.get_mut(id) {
            targets.retain(|target| *target != signer);
        }
        let done = membership
            .receipt_targets
            .get(id)
            .is_some_and(Vec::is_empty);
        if done {
            membership.receipt_targets.remove(id);
        }
        let retry_count = self
            .outbound_attempts
            .get(id)
            .map(|attempt| attempt.retry_count)
            .unwrap_or_default();
        if !own
            && self.messages.iter().any(|message| {
                message.message_id.as_deref() == Some(id) && message.from_device == self.device_id
            })
        {
            self.messages
                .mark_delivery(id, MessageDeliveryStatus::Delivered, None, retry_count)?;
        }
        if done {
            self.outbound_attempts.remove(id);
        }
        self.dirty_outbound.push(id.into());
        self.record_dirty = true;
        if !own {
            self.note_authenticated_frame("");
        }
        Ok(())
    }

    /// Live retries have the existing bounded budget. Offline catchup is issue 26.
    pub(in crate::private_dm_runtime) fn finish_device_resends(&mut self) -> Vec<String> {
        if !self.devices_live() {
            return Vec::new();
        }
        let done: Vec<_> = self
            .outbound_attempts
            .iter()
            .filter(|(id, attempt)| {
                attempt.auto_resends >= AUTO_RESEND_MAX
                    && self.messages.iter().any(|message| {
                        message.message_id.as_deref() == Some(id)
                            && message.delivery_status == Some(MessageDeliveryStatus::Delivered)
                    })
            })
            .map(|(id, _)| id.clone())
            .collect();
        for id in &done {
            self.outbound_attempts.remove(id);
            if let Some(membership) = &mut self.membership {
                membership.receipt_targets.remove(id);
            }
        }
        self.record_dirty |= !done.is_empty();
        done
    }
}
