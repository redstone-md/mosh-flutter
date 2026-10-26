//! One encrypted durable message-notification ledger, beside the existing history.
use super::*;
use crate::api::conversation::{BridgeConversationKind, BridgeConversationRef};
use serde::{Deserialize, Serialize};

const CONTROL: &str = "control-v1";
const MESSAGE_PREFIX: &str = "message/";
const RECENT_OCCURRENCES: usize = 64;

#[path = "background_delivery_read.rs"]
mod read;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[frb(non_opaque)]
pub struct BackgroundNotification {
    pub id: String,
    pub revision: u64,
    pub target: BridgeConversationRef,
    pub occurrence_id: String,
    pub sent_at_ms: u64,
    pub message_count: u32,
    pub sender: Option<String>,
    pub text: Option<String>,
}

/// Only the already-authenticated kind admission creates these facts.
pub(crate) struct BackgroundMessageAdmission {
    pub tables: HistoryTables,
    pub conversation_id: String,
    pub occurrence_id: String,
    pub message_id: String,
    pub sent_at_ms: u64,
}

#[derive(Serialize, Deserialize)]
struct Control {
    waiting_enabled: bool,
    interactive: bool,
}

#[derive(Serialize, Deserialize)]
struct Summary {
    id: String,
    revision: u64,
    target: BridgeConversationRef,
    occurrence_id: String,
    sent_at_ms: u64,
    message_id: String,
    message_count: u32,
    acknowledged: bool,
    recent_occurrences: Vec<String>,
}

impl Persistence {
    pub(crate) fn append_history_message_with_background(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
        message: Option<&BackgroundMessageAdmission>,
    ) -> Result<(), PersistenceError> {
        let key = Self::history_message_key(conversation_id, sent_at_ms, message_id);
        let blob = encrypt_blob(&self.dek, json)?;
        let changed = self.write(|tx| {
            let changed = message
                .map(|message| self.queue_background_message(tx, message))
                .transpose()?
                .unwrap_or(false);
            self.write_history_row(tx, tables, &key, &blob)?;
            Ok(changed)
        })?;
        if changed {
            crate::api::background::background_delivery_changed();
        }
        Ok(())
    }

    /// Absence is the upgrade baseline: old durable history never becomes a
    /// notification merely because this owner first opens its encrypted store.
    pub(crate) fn saved_background_intent(&self) -> Result<Option<bool>, PersistenceError> {
        Ok(self
            .background_row::<Control>(CONTROL)?
            .map(|row| row.waiting_enabled))
    }

    pub(crate) fn save_background_intent(
        &self,
        interactive: bool,
        waiting_enabled: bool,
    ) -> Result<(), PersistenceError> {
        let bytes = encode(&Control {
            interactive,
            waiting_enabled,
        })?;
        self.put(BACKGROUND_DELIVERY, CONTROL, &bytes)
    }

    /// Called before writing the history rows, in that SAME transaction. An
    /// existing row/tombstone or occurrence cannot manufacture a new alert.
    pub(crate) fn queue_background_message(
        &self,
        tx: &redb::WriteTransaction,
        message: &BackgroundMessageAdmission,
    ) -> Result<bool, PersistenceError> {
        let control: Option<Control> = self.background_tx_row(tx, CONTROL)?;
        if control.is_none_or(|control| control.interactive) {
            return Ok(false);
        }
        let row_key = Self::history_message_key(
            &message.conversation_id,
            message.sent_at_ms,
            &message.message_id,
        );
        if tx
            .open_table(message.tables.messages)
            .map_err(db_error)?
            .get(row_key.as_str())
            .map_err(db_error)?
            .is_some()
        {
            return Ok(false);
        }
        let key = format!(
            "{MESSAGE_PREFIX}{}/{}",
            message.tables.outbound_scope, message.conversation_id
        );
        let mut summary = self
            .background_tx_row::<Summary>(tx, &key)?
            .unwrap_or_else(|| Summary::new(message));
        if summary.recent_occurrences.contains(&message.occurrence_id) {
            return Ok(false);
        }
        summary.admit(message)?;
        let bytes = encrypt_blob(&self.dek, &encode(&summary)?)?;
        Self::update_row(tx, BACKGROUND_DELIVERY, &key, Some(&bytes))?;
        Ok(true)
    }

    fn background_row<T: serde::de::DeserializeOwned>(
        &self,
        key: &str,
    ) -> Result<Option<T>, PersistenceError> {
        self.get(BACKGROUND_DELIVERY, key)?
            .map(|bytes| decode(&bytes))
            .transpose()
    }

    fn background_tx_row<T: serde::de::DeserializeOwned>(
        &self,
        tx: &redb::WriteTransaction,
        key: &str,
    ) -> Result<Option<T>, PersistenceError> {
        let rows = tx.open_table(BACKGROUND_DELIVERY).map_err(db_error)?;
        let value = rows
            .get(key)
            .map_err(db_error)?
            .map(|row| decode(&decrypt_blob(&self.dek, row.value())?))
            .transpose();
        value
    }
}

impl Summary {
    fn admit(&mut self, message: &BackgroundMessageAdmission) -> Result<(), PersistenceError> {
        self.revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| PersistenceError::Json("background revision exhausted".into()))?;
        self.message_count = if self.acknowledged {
            1
        } else {
            self.message_count.saturating_add(1)
        };
        self.occurrence_id = message.occurrence_id.clone();
        self.sent_at_ms = message.sent_at_ms;
        self.message_id = message.message_id.clone();
        self.acknowledged = false;
        self.recent_occurrences.push(message.occurrence_id.clone());
        if self.recent_occurrences.len() > RECENT_OCCURRENCES {
            self.recent_occurrences.remove(0);
        }
        Ok(())
    }

    fn new(message: &BackgroundMessageAdmission) -> Self {
        let kind = match message.tables.outbound_scope {
            "private_dm" => BridgeConversationKind::Dm,
            "private_group" => BridgeConversationKind::Group,
            _ => BridgeConversationKind::Channel,
        };
        Self {
            id: format!("background-{}", hex::encode(rand::random::<[u8; 16]>())),
            revision: 0,
            target: BridgeConversationRef {
                kind,
                id: message.conversation_id.clone(),
            },
            occurrence_id: message.occurrence_id.clone(),
            sent_at_ms: message.sent_at_ms,
            message_id: message.message_id.clone(),
            message_count: 0,
            acknowledged: true,
            recent_occurrences: Vec::new(),
        }
    }
}

fn encode(value: &impl Serialize) -> Result<Vec<u8>, PersistenceError> {
    serde_json::to_vec(value).map_err(|error| PersistenceError::Json(error.to_string()))
}
fn decode<T: serde::de::DeserializeOwned>(value: &[u8]) -> Result<T, PersistenceError> {
    serde_json::from_slice(value).map_err(|error| PersistenceError::Json(error.to_string()))
}

#[cfg(test)]
#[path = "background_delivery_tests.rs"]
mod tests;
