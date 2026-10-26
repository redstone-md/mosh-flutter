//! Exact call buttons live in the existing encrypted delivery ledger.
use super::background_delivery::{decode, encode};
use super::*;
use crate::api::conversation::{BridgeConversationKind, BridgeConversationRef};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;

mod actions;
pub(crate) mod types;
pub(crate) use types::BackgroundCallState;
use types::CallRecord;
pub use types::{BackgroundCallAction, BackgroundCallNotification, BackgroundCallPhase};
const PREFIX: &str = "call/";

impl Persistence {
    /// Native authenticated state is flushed before reaching this boundary.
    /// Reclaimed calls become cancellation revisions, never obsolete fresh rings.
    pub(crate) fn sync_background_calls(
        &self,
        owner: &str,
        current: &[BackgroundCallState],
    ) -> Result<(), PersistenceError> {
        let changed = self.write(|tx| {
            let mut records = self.call_records(tx)?;
            let mut changed = false;
            let mut live = HashSet::new();
            for state in current {
                let key = call_key(state);
                live.insert(key.clone());
                let record = records.entry(key).or_insert_with(|| CallRecord {
                    id: format!(
                        "background-call-{}",
                        hex::encode(rand::random::<[u8; 16]>())
                    ),
                    owner: String::new(),
                    revision: 0,
                    acknowledged: false,
                    state: state.clone(),
                    answer: None,
                    decline: None,
                    hangup: None,
                });
                if record.owner != owner || record.state != *state {
                    record.replace(owner, state.clone())?;
                    changed = true;
                }
            }
            for (key, record) in records.iter_mut() {
                if !live.contains(key) && record.state.phase != BackgroundCallPhase::Ended {
                    let mut state = record.state.clone();
                    state.phase = BackgroundCallPhase::Ended;
                    state.expires_at_ms = 0;
                    record.replace(owner, state)?;
                    changed = true;
                }
            }
            if changed {
                self.write_call_records(tx, &records)?;
            }
            Ok(changed)
        })?;
        if changed {
            crate::api::background::background_delivery_changed();
        }
        Ok(())
    }

    pub(super) fn pending_call_notifications(
        &self,
        limit: usize,
    ) -> Result<Vec<BackgroundNotification>, PersistenceError> {
        let tx = self.db.begin_read().map_err(db_error)?;
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        let mut result = Vec::new();
        for row in rows.range(PREFIX.."call0").map_err(db_error)? {
            let (_, bytes) = row.map_err(db_error)?;
            let record: CallRecord = decode(&decrypt_blob(&self.dek, bytes.value())?)?;
            if !record.acknowledged {
                result.push(record.notification());
            }
            if result.len() == limit {
                break;
            }
        }
        Ok(result)
    }

    pub(super) fn ack_call_notification(
        &self,
        id: &str,
        revision: u64,
    ) -> Result<(), PersistenceError> {
        self.write(|tx| {
            let mut records = self.call_records(tx)?;
            for record in records.values_mut() {
                if record.id == id && record.revision == revision {
                    record.acknowledged = true;
                }
            }
            self.write_call_records(tx, &records)
        })
    }

    fn call_records(
        &self,
        tx: &redb::WriteTransaction,
    ) -> Result<std::collections::BTreeMap<String, CallRecord>, PersistenceError> {
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        rows.range(PREFIX.."call0")
            .map_err(db_error)?
            .map(|row| {
                let (key, bytes) = row.map_err(db_error)?;
                Ok((
                    key.value().to_owned(),
                    decode(&decrypt_blob(&self.dek, bytes.value())?)?,
                ))
            })
            .collect()
    }

    fn write_call_records(
        &self,
        tx: &redb::WriteTransaction,
        records: &std::collections::BTreeMap<String, CallRecord>,
    ) -> Result<(), PersistenceError> {
        for (key, record) in records {
            // Terminal acknowledged buttons have no future authority or replay work.
            let bytes = if record.acknowledged && record.state.phase == BackgroundCallPhase::Ended {
                None
            } else {
                Some(encrypt_blob(&self.dek, &encode(record)?)?)
            };
            Self::update_row(tx, BACKGROUND_DELIVERY, key, bytes.as_deref())?;
        }
        Ok(())
    }
}

fn call_key(state: &BackgroundCallState) -> String {
    let digest = Sha256::digest(format!("{}\0{}", state.session_id, state.call_id));
    format!("{PREFIX}{}", hex::encode(digest))
}

#[cfg(test)]
#[path = "background_call_tests.rs"]
mod tests;
