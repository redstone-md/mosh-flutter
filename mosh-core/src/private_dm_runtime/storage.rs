//! Atomic MLS records and acceptance of session updates.

use super::*;

impl ConversationSession for PrivateDmSession {
    type Message = ChatMessage;
    type Record = contracts::PersistedSession;

    fn conversation_id(&self) -> &str {
        &self.session_id
    }

    fn log(&self) -> &MessageLog<ChatMessage> {
        &self.messages
    }

    fn transfer(&self) -> Option<&Transfer> {
        Some(&self.transfer)
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.outbound_attempts
    }

    fn record(&self) -> contracts::PersistedSession {
        self.to_persisted_record()
    }

    fn write_extra(
        &self,
        persistence: &Persistence,
    ) -> Result<(), crate::persistence::PersistenceError> {
        if !self.record_is_final() {
            return persistence.put_mls_snapshot(&self.session_id, &self.crypto.snapshot());
        }
        let record = serde_json::to_vec(&self.to_persisted_record())
            .map_err(|error| crate::persistence::PersistenceError::Json(error.to_string()))?;
        // Receipt replay needs the accepted record and its receiver ratchet.
        // The shared writer may safely repeat this same record afterward.
        persistence.put_dm_transition(&self.session_id, &record, &self.crypto.snapshot())
    }

    /// Until the joiner processes the Welcome its record's group id is an
    /// empty placeholder, and a session saved in that state cannot be rebuilt.
    fn record_is_final(&self) -> bool {
        self.crypto.group_id_bytes().is_some()
            || self
                .membership
                .as_ref()
                .is_some_and(|membership| membership.is_joining())
    }

    fn record_changed(&self) -> bool {
        self.record_dirty
    }

    fn record_written(&mut self) {
        self.record_dirty = false;
    }
}
