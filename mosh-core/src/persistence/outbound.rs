//! Durable outbound attempts and atomic message acceptance.
use super::*;

impl Persistence {
    pub(super) fn outbound_attempt_prefix(scope: &str, conversation_id: &str) -> String {
        format!("{scope}\u{0001}{conversation_id}")
    }

    pub(super) fn outbound_attempt_key(
        scope: &str,
        conversation_id: &str,
        message_id: &str,
    ) -> String {
        format!(
            "{}\u{0001}{message_id}",
            Self::outbound_attempt_prefix(scope, conversation_id)
        )
    }

    pub fn put_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        let tables = match scope {
            "private_dm" => DM_HISTORY,
            "private_group" => GROUP_HISTORY,
            "channel" => CHANNEL_HISTORY,
            _ => return Err(PersistenceError::Db("invalid outbound scope".into())),
        };
        self.write(|tx| {
            self.write_outbound_row(tx, tables, conversation_id, message_id, Some(json))
        })
    }

    pub fn get_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        let key = Self::outbound_attempt_key(scope, conversation_id, message_id);
        self.get(OUTBOUND_ATTEMPTS, &key)
    }

    pub fn list_outbound_attempts(
        &self,
        scope: &str,
        conversation_id: &str,
    ) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.range_prefix(
            OUTBOUND_ATTEMPTS,
            &Self::outbound_attempt_prefix(scope, conversation_id),
        )
    }

    pub fn delete_outbound_attempt(
        &self,
        scope: &str,
        conversation_id: &str,
        message_id: &str,
    ) -> Result<(), PersistenceError> {
        let key = Self::outbound_attempt_key(scope, conversation_id, message_id);
        self.write(|tx| Self::update_row(tx, OUTBOUND_ATTEMPTS, &key, None))
    }

    /// The history row and its replay attempt are one durable fact.
    pub fn commit_send(
        &self,
        tables: HistoryTables,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        message_json: &[u8],
        attempt_json: Option<&[u8]>,
    ) -> Result<(), PersistenceError> {
        let message_key = Self::history_message_key(conversation_id, sent_at_ms, message_id);
        let message = encrypt_blob(&self.dek, message_json)?;
        self.write(|tx| {
            self.write_history_row(tx, tables, &message_key, &message)?;
            self.write_outbound_row(tx, tables, conversation_id, message_id, attempt_json)
        })
    }
}
