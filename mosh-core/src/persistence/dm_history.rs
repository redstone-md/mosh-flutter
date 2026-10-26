//! Import text and its continuation cursor in one locally encrypted transaction.
use super::*;
use crate::conversation::history::StoredMessage;
impl Persistence {
    pub(crate) fn get_dm_history_message(
        &self,
        session: &str,
        sent_at_ms: u64,
        message_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(
            MESSAGES,
            &Self::history_message_key(session, sent_at_ms, message_id),
        )
    }

    pub(crate) fn commit_dm_history_import<M: serde::Serialize>(
        &self,
        session: &str,
        record: &[u8],
        messages: &[StoredMessage<M>],
    ) -> Result<(), PersistenceError> {
        self.commit_history_admission(
            DM_HISTORY,
            session,
            HistoryAdmission {
                state: Some((session, record)),
                ..Default::default()
            },
            messages,
        )
    }
}
