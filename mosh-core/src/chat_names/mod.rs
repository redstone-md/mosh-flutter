//! Durable personal names. Network authentication belongs to the device-link owner.
pub(crate) mod types;
pub use types::{
    validate_chat_name, ChatNameEntry, ChatNameError, ChatNameErrorKind, ChatNameSnapshot,
};
use types::{validate_key, Result};
pub(crate) use types::{NameRecord, NameVersion};

use crate::persistence::Persistence;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::Arc;

#[derive(Default, Clone, Serialize, Deserialize)]
struct Register {
    clock: u64,
    #[serde(default)]
    initial_sync_complete: bool,
    entries: BTreeMap<String, NameRecord>,
}

pub struct ChatNames {
    store: Arc<Persistence>,
    user: String,
    actor: String,
    register: Register,
}

impl ChatNames {
    pub fn open(store: Arc<Persistence>, user: &str, actor: &str) -> Result<Self> {
        let register = store
            .get_chat_names(user)
            .map_err(ChatNameError::storage)?
            .map(|bytes| serde_json::from_slice::<Register>(&bytes).map_err(ChatNameError::storage))
            .transpose()?
            .unwrap_or_default();
        for (key, entry) in &register.entries {
            entry.validate()?;
            if key != &entry.key || entry.version.counter > register.clock {
                return Err(ChatNameError::invalid());
            }
        }
        Ok(Self {
            store,
            user: user.into(),
            actor: actor.into(),
            register,
        })
    }

    pub fn name(&self, key: &str) -> Option<&str> {
        self.register.entries.get(key)?.name.as_deref()
    }

    pub(crate) fn user(&self) -> &str {
        &self.user
    }

    pub(crate) fn initial_sync_complete(&self) -> bool {
        self.register.initial_sync_complete
    }

    pub fn snapshot(&self, pending: bool) -> ChatNameSnapshot {
        ChatNameSnapshot {
            entries: self
                .register
                .entries
                .values()
                .filter_map(|entry| {
                    entry.name.as_ref().map(|name| ChatNameEntry {
                        conversation_key: entry.key.clone(),
                        name: name.clone(),
                    })
                })
                .collect(),
            pending,
        }
    }

    pub fn rename(&mut self, key: &str, name: &str) -> Result<()> {
        self.set(key, Some(validate_chat_name(name)?))
    }

    pub fn reset(&mut self, key: &str) -> Result<()> {
        self.set(key, None)
    }

    fn set(&mut self, key: &str, name: Option<String>) -> Result<()> {
        validate_key(key)?;
        if self.name(key) == name.as_deref() {
            return Ok(());
        }
        let counter = self
            .register
            .clock
            .checked_add(1)
            .filter(|n| *n < u64::MAX)
            .ok_or_else(ChatNameError::invalid)?;
        self.merge(
            &[NameRecord {
                key: key.into(),
                name,
                version: NameVersion {
                    counter,
                    actor: self.actor.clone(),
                },
            }],
            true,
        )?;
        Ok(())
    }

    /// Caller authenticates the account and active sender before importing a batch.
    pub(crate) fn merge(
        &mut self,
        records: &[NameRecord],
        initial_sync_complete: bool,
    ) -> Result<bool> {
        let mut next = self.register.clone();
        let mut changed = initial_sync_complete && !next.initial_sync_complete;
        next.initial_sync_complete |= initial_sync_complete;
        for entry in records {
            entry.validate()?;
            let previous = next.entries.get(&entry.key);
            if previous.is_some_and(|old| old.version == entry.version && old != entry) {
                return Err(ChatNameError::invalid());
            }
            if previous.is_none_or(|old| old.version < entry.version) {
                next.clock = next.clock.max(entry.version.counter);
                next.entries.insert(entry.key.clone(), entry.clone());
                changed = true;
            }
        }
        if changed {
            let bytes = serde_json::to_vec(&next).map_err(ChatNameError::storage)?;
            self.store
                .put_chat_names(&self.user, &bytes)
                .map_err(ChatNameError::storage)?;
            self.register = next;
        }
        Ok(changed)
    }

    pub(crate) fn page(&self, after: Option<&str>) -> Vec<NameRecord> {
        self.register
            .entries
            .values()
            .filter(|entry| after.is_none_or(|key| entry.key.as_str() > key))
            .take(16)
            .cloned()
            .collect()
    }

    pub(crate) fn digest(&self) -> String {
        use sha2::{Digest, Sha256};
        hex::encode(Sha256::digest(
            serde_json::to_vec(&self.register.entries).expect("name register serializes"),
        ))
    }
}
