//! Existing kind-specific entry points delegate to shared history operations.
use super::*;

impl Persistence {
    pub fn put_mls_snapshot(
        &self,
        session_id: &str,
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(MLS_SNAPSHOT, session_id, snapshot)
    }

    pub fn get_mls_snapshot(&self, session_id: &str) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(MLS_SNAPSHOT, session_id)
    }

    pub fn put_session(&self, session_id: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(DM_HISTORY, session_id, json)
    }

    pub fn list_sessions(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(DM_HISTORY)
    }

    pub fn append_message(
        &self,
        conversation_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(DM_HISTORY, conversation_id, sent_at_ms, message_id, json)
    }

    pub fn list_messages(&self, conversation_id: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(DM_HISTORY, conversation_id)
    }

    pub fn put_group_mls_snapshot(
        &self,
        group_id: &str,
        snapshot: &[u8],
    ) -> Result<(), PersistenceError> {
        self.put(GROUP_MLS_SNAPSHOT, group_id, snapshot)
    }

    pub fn get_group_mls_snapshot(
        &self,
        group_id: &str,
    ) -> Result<Option<Vec<u8>>, PersistenceError> {
        self.get(GROUP_MLS_SNAPSHOT, group_id)
    }

    pub fn put_group(&self, group_id: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(GROUP_HISTORY, group_id, json)
    }

    pub fn list_groups(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(GROUP_HISTORY)
    }

    pub fn append_group_message(
        &self,
        group_id: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(GROUP_HISTORY, group_id, sent_at_ms, message_id, json)
    }

    pub fn list_group_messages(&self, group_id: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(GROUP_HISTORY, group_id)
    }

    pub fn put_channel(&self, name: &str, json: &[u8]) -> Result<(), PersistenceError> {
        self.put_conversation(CHANNEL_HISTORY, name, json)
    }

    pub fn list_channels(&self) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_conversations(CHANNEL_HISTORY)
    }

    pub fn append_channel_message(
        &self,
        name: &str,
        sent_at_ms: u64,
        message_id: &str,
        json: &[u8],
    ) -> Result<(), PersistenceError> {
        self.append_history_message(CHANNEL_HISTORY, name, sent_at_ms, message_id, json)
    }

    pub fn list_channel_messages(&self, name: &str) -> Result<Vec<Vec<u8>>, PersistenceError> {
        self.list_history_messages(CHANNEL_HISTORY, name)
    }

    pub fn delete_session(&self, session_id: &str) -> Result<(), PersistenceError> {
        self.delete_conversation(DM_HISTORY, session_id)
    }

    pub fn delete_group(&self, group_id: &str) -> Result<(), PersistenceError> {
        self.delete_conversation(GROUP_HISTORY, group_id)
    }

    pub fn delete_channel(&self, name: &str) -> Result<(), PersistenceError> {
        self.delete_conversation(CHANNEL_HISTORY, name)
    }
}
