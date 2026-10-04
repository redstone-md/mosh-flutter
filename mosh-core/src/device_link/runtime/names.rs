use super::*;
use crate::chat_names::{ChatNameError, ChatNameErrorKind, ChatNameSnapshot, NameRecord};
use crate::device_link::identity::storage_error;
use crate::device_link::names_wire::{self, NameMessage};
use rand::RngCore;

pub(super) struct NamePageRequest {
    pub(super) request_id: [u8; 16],
    pub(super) roster_hash: String,
    after: Option<String>,
}

impl NamePageRequest {
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
        NameMessage::Request {
            after: self.after.clone(),
            request_id: self.request_id,
        }
    }
}

impl DeviceLinkRuntime {
    pub fn chat_names_snapshot(&mut self) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        self.service()?;
        self.current_names_snapshot()
    }

    fn current_names_snapshot(&self) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        let digest = self.names.digest();
        let pending = self.identity.roster().devices()?.iter().any(|device| {
            device.device_id != self.identity.device().device_id
                && (!self.names.initial_sync_complete()
                    || self.names_peer_digests.get(&device.device_id) != Some(&digest))
        });
        Ok(self
            .names
            .snapshot(pending, self.require_active_name_writer().is_ok()))
    }

    pub fn rename_chat(
        &mut self,
        key: &str,
        name: &str,
    ) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        self.service()?;
        self.require_active_name_writer()?;
        self.names.rename(key, name)?;
        self.names_last_pull = None;
        self.current_names_snapshot()
    }

    pub fn reset_chat_name(
        &mut self,
        key: &str,
    ) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        self.service()?;
        self.require_active_name_writer()?;
        self.names.reset(key)?;
        self.names_last_pull = None;
        self.current_names_snapshot()
    }

    fn require_active_name_writer(&self) -> std::result::Result<(), ChatNameError> {
        if self.identity.revoked()? {
            return Err(ChatNameError::new(
                ChatNameErrorKind::Unauthorized,
                "device no longer belongs to this user",
            ));
        }
        if !self.names.initial_sync_complete() && self.identity.roster().devices()?.len() > 1 {
            return Err(ChatNameError::new(
                ChatNameErrorKind::Unavailable,
                "chat names are still synchronizing; try again in a moment",
            ));
        }
        Ok(())
    }

    pub(super) fn reload_names(&mut self) -> Result<()> {
        if self.names.user() != self.identity.roster().user_id() {
            self.names = self.identity.chat_names().map_err(storage_error)?;
            self.names_peer_digests.clear();
            self.names_initial_pulls.clear();
            self.names_pending_pages.clear();
            self.names_last_pull = None;
        }
        Ok(())
    }

    pub(super) fn sync_names(&mut self) -> Result<()> {
        self.reload_names()?;
        if self.identity.revoked()?
            || self
                .names_last_pull
                .is_some_and(|t| t.elapsed() < std::time::Duration::from_secs(2))
        {
            return Ok(());
        }
        self.names_last_pull = Some(Instant::now());
        let digest = self.names.digest();
        let roster_hash = self.identity.roster().digest()?;
        for device in self.identity.roster().devices()? {
            if device.device_id != self.identity.device().device_id
                && (!self.names.initial_sync_complete()
                    || self.names_peer_digests.get(&device.device_id) != Some(&digest))
            {
                let page = self
                    .names_pending_pages
                    .entry(device.device_id.clone())
                    .or_insert_with(|| NamePageRequest::new(roster_hash.clone(), None));
                if page.roster_hash != roster_hash {
                    *page = NamePageRequest::new(roster_hash.clone(), None);
                }
                let message = page.message();
                self.send_names(&device, message);
            }
        }
        Ok(())
    }

    fn send_names(&mut self, device: &DeviceDescriptor, message: NameMessage) {
        if let Ok(packet) = names_wire::seal(&self.identity, &device.device_id, message) {
            let _ = self.transport.send(&device.moss_peer_id, &packet);
        }
    }

    fn merge_name_page(
        &mut self,
        sender: &DeviceDescriptor,
        records: &[NameRecord],
        last_page: bool,
    ) -> Result<()> {
        let roster_hash = self.identity.roster().digest()?;
        let complete = last_page
            && self.identity.roster().devices()?.iter().all(|device| {
                device.device_id == self.identity.device().device_id
                    || device.device_id == sender.device_id
                    || self.names_initial_pulls.get(&device.device_id) == Some(&roster_hash)
            });
        self.names
            .merge(records, complete)
            .map_err(|error| match error.kind {
                ChatNameErrorKind::Storage => storage_error(error),
                _ => super::super::roster::invalid(),
            })?;
        // Track only saved pages from the current authenticated roster.
        if self.names.initial_sync_complete() {
            self.names_initial_pulls.clear();
        } else if last_page {
            self.names_initial_pulls
                .insert(sender.device_id.clone(), roster_hash);
        }
        Ok(())
    }

    fn receive_name_page(
        &mut self,
        sender: &DeviceDescriptor,
        records: &[NameRecord],
        next: Option<String>,
        request_id: [u8; 16],
    ) -> Result<()> {
        let roster_hash = self.identity.roster().digest()?;
        if !self
            .names_pending_pages
            .get(&sender.device_id)
            .is_some_and(|page| page.request_id == request_id && page.roster_hash == roster_hash)
        {
            return Ok(());
        }
        self.merge_name_page(sender, records, next.is_none())?;
        if let Some(after) = next {
            let page = NamePageRequest::new(roster_hash, Some(after));
            let message = page.message();
            self.names_pending_pages
                .insert(sender.device_id.clone(), page);
            self.send_names(sender, message);
        } else {
            self.names_pending_pages.remove(&sender.device_id);
            self.send_names(
                sender,
                NameMessage::Saved {
                    digest: self.names.digest(),
                },
            );
        }
        Ok(())
    }

    pub(super) fn receive_names(&mut self, packet: &[u8]) -> Result<bool> {
        if !packet.starts_with(names_wire::PREFIX) {
            return Ok(false);
        }
        self.reload_names()?;
        let (sender, message) = names_wire::open(&self.identity, packet)?;
        match message {
            NameMessage::Request { after, request_id } => {
                // Advertise our durable state so a restarting initiator can
                // stop pulling without forcing a reciprocal request loop.
                if after.is_none() {
                    self.send_names(
                        &sender,
                        NameMessage::Saved {
                            digest: self.names.digest(),
                        },
                    );
                }
                let records = self.names.page(after.as_deref());
                let next = (records.len() == 16).then(|| records.last().unwrap().key.clone());
                self.send_names(
                    &sender,
                    NameMessage::Batch {
                        records,
                        next,
                        request_id,
                    },
                );
            }
            NameMessage::Batch {
                records,
                next,
                request_id,
            } if records.len() <= 16 => {
                self.receive_name_page(&sender, &records, next, request_id)?;
            }
            NameMessage::Saved { digest } => {
                self.names_peer_digests.insert(sender.device_id, digest);
            }
            _ => {}
        }
        Ok(true)
    }
}
