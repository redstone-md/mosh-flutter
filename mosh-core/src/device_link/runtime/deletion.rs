use super::*;
use crate::device_link::{identity::storage_error, names_wire::NameMessage, roster::invalid};
use crate::message_deletion::DeletionRecord;
use rand::RngCore;
use sha2::{Digest, Sha256};

pub(super) struct DeletionPage {
    pub(super) request_id: [u8; 16],
    roster_hash: String,
    after: Option<String>,
}

impl DeletionPage {
    fn new(roster_hash: String, after: Option<String>) -> Self {
        let mut request_id = [0; 16];
        rand::rngs::OsRng.fill_bytes(&mut request_id);
        Self {
            request_id,
            roster_hash,
            after,
        }
    }
    fn message(&self) -> NameMessage {
        NameMessage::DeletionRequest {
            after: self.after.clone(),
            request_id: self.request_id,
        }
    }
}

impl DeviceLinkRuntime {
    fn deletion_records(&self) -> Result<Vec<DeletionRecord>> {
        self.identity
            .persistence()
            .account_deletions(&self.identity.roster().user_id())
            .map_err(storage_error)
    }
    fn deletion_digest(&self) -> Result<String> {
        Ok(hex::encode(Sha256::digest(
            serde_json::to_vec(&self.deletion_records()?).map_err(storage_error)?,
        )))
    }

    pub(super) fn sync_deletions(&mut self) -> Result<()> {
        if self.identity.revoked()?
            || self
                .deletion_last_pull
                .is_some_and(|t| t.elapsed().as_secs() < 2)
        {
            return Ok(());
        }
        self.deletion_last_pull = Some(Instant::now());
        let digest = self.deletion_digest()?;
        let roster_hash = self.identity.roster().digest()?;
        for device in self.identity.roster().devices()? {
            if device.device_id == self.identity.device().device_id {
                continue;
            }
            if self.deletion_digests.get(&device.device_id) == Some(&digest) {
                continue;
            }
            let page = self
                .deletion_pages
                .entry(device.device_id.clone())
                .or_insert_with(|| DeletionPage::new(roster_hash.clone(), None));
            if page.roster_hash != roster_hash {
                *page = DeletionPage::new(roster_hash.clone(), None);
            }
            let message = page.message();
            self.send_names(&device, message);
        }
        Ok(())
    }

    pub(super) fn receive_deletions(
        &mut self,
        sender: &DeviceDescriptor,
        message: NameMessage,
    ) -> Result<()> {
        match message {
            NameMessage::DeletionFragment { fragment } => {
                if let Some(bytes) = self
                    .deletion_fragments
                    .add(&sender.device_id, fragment)
                    .map_err(|_| invalid())?
                {
                    let message: NameMessage =
                        serde_json::from_slice(&bytes).map_err(|_| invalid())?;
                    if !matches!(message, NameMessage::DeletionBatch { .. }) {
                        return Err(invalid());
                    }
                    self.receive_deletions(sender, message)?;
                }
            }
            NameMessage::DeletionRequest { after, request_id } => {
                let (records, next) = self.deletion_page(after.as_deref())?;
                self.send_names(
                    sender,
                    NameMessage::DeletionBatch {
                        records,
                        next,
                        request_id,
                    },
                );
            }
            NameMessage::DeletionBatch {
                records,
                next,
                request_id,
            } => {
                self.save_deletion_page(sender, records, next, request_id)?;
            }
            NameMessage::DeletionSaved { digest } => {
                self.deletion_digests
                    .insert(sender.device_id.clone(), digest);
            }
            _ => return Err(invalid()),
        }
        Ok(())
    }

    fn deletion_page(&self, after: Option<&str>) -> Result<(Vec<DeletionRecord>, Option<String>)> {
        self.identity
            .persistence()
            .account_deletion_page(&self.identity.roster().user_id(), after)
            .map_err(storage_error)
    }

    fn save_deletion_page(
        &mut self,
        sender: &DeviceDescriptor,
        records: Vec<DeletionRecord>,
        next: Option<String>,
        request_id: [u8; 16],
    ) -> Result<()> {
        let roster_hash = self.identity.roster().digest()?;
        if !self
            .deletion_pages
            .get(&sender.device_id)
            .is_some_and(|p| p.request_id == request_id && p.roster_hash == roster_hash)
        {
            return Ok(());
        }
        if records.len() > 16 || next.as_ref().is_some_and(|n| n.len() > 1024) {
            return Err(invalid());
        }
        self.identity
            .persistence()
            .save_account_deletions(&self.identity.roster().user_id(), &records)
            .map_err(storage_error)?;
        if let Some(after) = next {
            let page = DeletionPage::new(roster_hash, Some(after));
            let message = page.message();
            self.deletion_pages.insert(sender.device_id.clone(), page);
            self.send_names(sender, message);
        } else {
            self.deletion_pages.remove(&sender.device_id);
            self.send_names(
                sender,
                NameMessage::DeletionSaved {
                    digest: self.deletion_digest()?,
                },
            );
        }
        Ok(())
    }
}
