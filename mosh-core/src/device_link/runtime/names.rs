use super::*;
use crate::chat_names::{ChatNameError, ChatNameErrorKind, ChatNameSnapshot};
use crate::device_link::identity::storage_error;
use crate::device_link::names_wire::{self, NameMessage};

impl DeviceLinkRuntime {
    pub fn chat_names_snapshot(&mut self) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        self.service()?;
        self.current_names_snapshot()
    }

    fn current_names_snapshot(&self) -> std::result::Result<ChatNameSnapshot, ChatNameError> {
        let digest = self.names.digest();
        let pending = self.identity.roster().devices()?.iter().any(|device| {
            device.device_id != self.identity.device().device_id
                && self.names_peer_digests.get(&device.device_id) != Some(&digest)
        });
        Ok(self.names.snapshot(pending))
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
        Ok(())
    }

    pub(super) fn reload_names(&mut self) -> Result<()> {
        if self.names.user() != self.identity.roster().user_id() {
            self.names = self.identity.chat_names().map_err(storage_error)?;
            self.names_peer_digests.clear();
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
        for device in self.identity.roster().devices()? {
            if device.device_id != self.identity.device().device_id {
                self.send_names(&device, NameMessage::Request { after: None });
            }
        }
        Ok(())
    }

    fn send_names(&mut self, device: &DeviceDescriptor, message: NameMessage) {
        if let Ok(packet) = names_wire::seal(&self.identity, &device.device_id, message) {
            let _ = self.transport.send(&device.moss_peer_id, &packet);
        }
    }

    pub(super) fn receive_names(&mut self, packet: &[u8]) -> Result<bool> {
        if !packet.starts_with(names_wire::PREFIX) {
            return Ok(false);
        }
        self.reload_names()?;
        let (sender, message) = names_wire::open(&self.identity, packet)?;
        match message {
            NameMessage::Request { after } => {
                let records = self.names.page(after.as_deref());
                let next = (records.len() == 16).then(|| records.last().unwrap().key.clone());
                self.send_names(&sender, NameMessage::Batch { records, next });
            }
            NameMessage::Batch { records, next } if records.len() <= 16 => {
                self.names
                    .merge(&records)
                    .map_err(|error| match error.kind {
                        ChatNameErrorKind::Storage => storage_error(error),
                        _ => super::super::roster::invalid(),
                    })?;
                match next {
                    Some(after) => {
                        self.send_names(&sender, NameMessage::Request { after: Some(after) })
                    }
                    None => self.send_names(
                        &sender,
                        NameMessage::Saved {
                            digest: self.names.digest(),
                        },
                    ),
                }
            }
            NameMessage::Saved { digest } => {
                self.names_peer_digests.insert(sender.device_id, digest);
            }
            _ => {}
        }
        Ok(true)
    }
}
