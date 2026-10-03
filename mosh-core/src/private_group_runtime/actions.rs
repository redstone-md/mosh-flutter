//! Attachment commands, DM offers and org-bound group closure.

use super::*;

impl PrivateGroupRuntime {
    /// Encrypts a file, stores the sender's copy, and broadcasts the manifest
    /// to every group member over the MLS-protected control channel.
    pub fn send_attachment(
        &mut self,
        group_id: &str,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        let result = session.send_attachment(file_name, mime, bytes, thumbnail, voice)?;
        self.groups.persist_tail_logged(KIND);
        Ok(result)
    }

    pub fn download_attachment(
        &mut self,
        group_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        session.transfer.start_download(attachment_id)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        group_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        Ok(session.transfer.cancel(attachment_id)?)
    }

    /// Publishes a private-DM invitation aimed at one group member.
    pub fn send_dm_offer(
        &mut self,
        group_id: &str,
        target_fingerprint: String,
        invite_uri: String,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        let offer = DmOffers::mint(
            session.display_name.clone(),
            session.device_fingerprint.clone(),
            target_fingerprint,
            invite_uri,
        );
        session.publish_control(&ControlEnvelope::DmOffer {
            group_id: session.group_id.clone(),
            offer,
        })
    }

    /// Leaving an org closes every group bound to it — otherwise the
    /// sessions would freeze (roster gone ⇒ no commit is ever authorized
    /// again) while still appearing live.
    pub fn close_org_groups(&mut self, org_pubkey: &str) {
        let bound: Vec<String> = self
            .groups
            .values()
            .filter(|session| session.org_pubkey.as_deref() == Some(org_pubkey))
            .map(|session| session.group_id.clone())
            .collect();
        for group_id in bound {
            if let Err(error) = self.close(&group_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::ROOM,
                    &group_id,
                    &format!("close on org leave failed: {error}"),
                );
            }
        }
    }

    pub fn dismiss_dm_offer(
        &mut self,
        group_id: &str,
        offer_id: &str,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        session.dm_offers.dismiss(offer_id);
        Ok(())
    }

    /// Serves a byte range for streaming playback of a group attachment.
    pub fn stream_attachment_range(
        &mut self,
        group_id: &str,
        attachment_id: &str,
        start: u64,
        end: u64,
    ) -> Result<StreamRange, PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        let outcome = session.transfer.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }
}
