use super::*;
use crate::device_link::{
    identity::storage_error,
    names_wire::NameMessage,
    roster::{device_id, public_key},
};
use crate::plus::global;
use rand::RngCore;
use std::collections::HashMap;

#[derive(Default)]
pub(super) struct SyncState {
    account: String,
    roster: String,
    last_pull: Option<Instant>,
    digests: HashMap<String, String>,
    pending: HashMap<String, PageRequest>,
}

struct PageRequest {
    id: [u8; 16],
    after: Option<String>,
}

impl PageRequest {
    fn new(after: Option<String>) -> Self {
        let mut id = [0; 16];
        rand::rngs::OsRng.fill_bytes(&mut id);
        Self { id, after }
    }

    fn message(&self) -> NameMessage {
        NameMessage::PlusRequest {
            after: self.after.clone(),
            request_id: self.id,
        }
    }
}

impl DeviceLinkRuntime {
    pub(super) fn reload_plus(&mut self) -> Result<()> {
        let account = self.identity.roster().user_id();
        let roster = self.identity.roster().digest()?;
        if self.plus_sync.account != account || self.plus_sync.roster != roster {
            self.plus_sync = SyncState {
                account: account.clone(),
                roster: roster.clone(),
                ..Default::default()
            };
        }
        let initializer = device_id(&public_key(&account)?);
        let members: Vec<_> = self
            .identity
            .roster()
            .devices()?
            .into_iter()
            .map(|d| d.device_id)
            .collect();
        global::reconcile_roster(
            &account,
            &self.identity.device().device_id,
            &roster,
            &initializer,
            &members,
        )
        .map_err(storage_error)
    }

    pub(super) fn sync_plus(&mut self) -> Result<()> {
        if self.identity.revoked()?
            || self
                .plus_sync
                .last_pull
                .is_some_and(|t| t.elapsed() < std::time::Duration::from_secs(2))
        {
            return Ok(());
        }
        let Some(digest) = global::with_sync(&self.identity.roster().user_id(), |owner| {
            owner.sync_digest()
        })
        .map_err(storage_error)?
        else {
            return Ok(());
        };
        self.plus_sync.last_pull = Some(Instant::now());
        for device in self.identity.roster().devices()? {
            if device.device_id == self.identity.device().device_id
                || self.plus_sync.digests.get(&device.device_id) == Some(&digest)
            {
                continue;
            }
            let page = self
                .plus_sync
                .pending
                .entry(device.device_id.clone())
                .or_insert_with(|| PageRequest::new(None));
            let message = page.message();
            self.send_names(&device, message);
        }
        Ok(())
    }

    pub(super) fn receive_plus(
        &mut self,
        sender: &DeviceDescriptor,
        message: NameMessage,
    ) -> Result<()> {
        let account = self.identity.roster().user_id();
        match message {
            NameMessage::PlusRequest { after, request_id } => {
                let page = global::with_sync(&account, |owner| owner.export_sync(after.as_deref()))
                    .map_err(storage_error)?
                    .flatten();
                if let Some(page) = page {
                    self.send_plus_saved(sender)?;
                    self.send_names(sender, NameMessage::PlusBatch { page, request_id });
                }
            }
            NameMessage::PlusBatch { page, request_id }
                if self
                    .plus_sync
                    .pending
                    .get(&sender.device_id)
                    .is_some_and(|p| p.id == request_id) =>
            {
                self.receive_plus_page(sender, &account, &page)?;
            }
            NameMessage::PlusSaved {
                digest,
                series_digest,
            } if digest.len() == 64 && series_digest.len() == 64 => {
                self.plus_sync
                    .digests
                    .insert(sender.device_id.clone(), digest);
                global::with_sync(&account, |owner| {
                    owner.acknowledge_sync(&sender.device_id, &series_digest)
                })
                .map_err(storage_error)?;
            }
            _ => {}
        }
        Ok(())
    }

    fn receive_plus_page(
        &mut self,
        sender: &DeviceDescriptor,
        account: &str,
        page: &str,
    ) -> Result<()> {
        let Some(next) = global::with_sync(account, |owner| owner.merge_sync(page))
            .map_err(|_| super::super::roster::invalid())?
        else {
            return Ok(());
        };
        if let Some(after) = next {
            let page = PageRequest::new(Some(after));
            let message = page.message();
            self.plus_sync
                .pending
                .insert(sender.device_id.clone(), page);
            self.send_names(sender, message);
        } else {
            self.plus_sync.pending.remove(&sender.device_id);
            self.send_plus_saved(sender)?;
        }
        Ok(())
    }

    fn send_plus_saved(&mut self, peer: &DeviceDescriptor) -> Result<()> {
        if let Some((digest, series_digest)) =
            global::with_sync(&self.identity.roster().user_id(), |owner| {
                Ok((owner.sync_digest()?, owner.series_digest()?))
            })
            .map_err(storage_error)?
        {
            self.send_names(
                peer,
                NameMessage::PlusSaved {
                    digest,
                    series_digest,
                },
            );
        }
        Ok(())
    }
}
