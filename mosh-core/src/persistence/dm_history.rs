//! Import text and its continuation cursor in one locally encrypted transaction.
use super::*;
use crate::conversation::{
    history::{background, StoredMessage},
    message_log::ConversationMessage,
};
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

    pub(crate) fn commit_dm_history_import<M: ConversationMessage>(
        &self,
        session: &str,
        record: &[u8],
        messages: &[StoredMessage<M>],
    ) -> Result<(), PersistenceError> {
        let background_messages: Vec<_> = messages
            .iter()
            .filter_map(|row| {
                background::message(
                    DM_HISTORY,
                    session,
                    row.sent_at_ms,
                    &row.message_id,
                    &row.message,
                )
            })
            .collect();
        self.commit_history_admission(
            DM_HISTORY,
            session,
            HistoryAdmission {
                state: Some((session, record)),
                background_messages: &background_messages,
                ..Default::default()
            },
            messages,
        )
    }
}
