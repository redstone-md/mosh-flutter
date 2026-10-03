//! The shared owner of writes that have not received durable acceptance.
use super::*;

#[derive(Clone, Copy, Default)]
struct StateWrite {
    extra: bool,
    record: bool,
    finalize: bool,
}

#[derive(Default)]
pub(super) struct PendingWrites {
    sends: HashMap<(String, String), bool>,
    state: HashMap<String, StateWrite>,
}

impl PendingWrites {
    pub(super) fn forget(&mut self, conversation_id: &str) {
        self.sends.retain(|(id, _), _| id != conversation_id);
        self.state.remove(conversation_id);
    }

    fn request_state(&mut self, id: &str, extra: bool, record: bool, finalize: bool) {
        if extra || record {
            let pending = self.state.entry(id.to_string()).or_default();
            pending.extra |= extra;
            pending.record |= record;
            pending.finalize |= finalize;
        }
    }
}

impl<S: ConversationSession> ConversationRuntime<S> {
    /// Keep reads and completed publications available while refused writes
    /// remain pending for a later retry.
    pub(crate) fn persist_tail_logged(&mut self, scope: &str) {
        if let Err(error) = self.persist_tail() {
            dlog::write(LogLevel::Error, kinds::PERSIST, scope, &error.to_string());
        }
    }

    /// Retry refused writes and append new rows. A refusal in one conversation
    /// does not prevent the remaining conversations from saving their state.
    pub fn persist_tail(&mut self) -> Result<(), PersistenceError> {
        let Some(store) = self.persistence.clone() else {
            return Ok(());
        };
        let mut first_error = None;
        let mut refused = HashSet::new();
        let sends: Vec<_> = self.pending.sends.clone().into_iter().collect();
        for ((id, message), deep) in sends {
            if let Err(error) = self.persist_send(&id, &message, deep) {
                refused.insert(id);
                first_error.get_or_insert(error);
            }
        }
        let ids: Vec<_> = self.sessions.keys().cloned().collect();
        for id in ids {
            if refused.contains(&id) {
                continue;
            }
            if let Err(error) = self.persist_session_tail(&store, &id) {
                first_error.get_or_insert(error);
            }
        }
        first_error.map_or(Ok(()), Err)
    }

    /// Save provisional admission before a DM can become automatically queued.
    /// Pending replay becomes Failed if a commit outcome is uncertain.
    pub(crate) fn persist_admission(
        &self,
        conversation_id: &str,
        message_id: &str,
    ) -> Result<(), PersistenceError> {
        let Some(store) = &self.persistence else {
            return Ok(());
        };
        let Some(session) = self.sessions.get(conversation_id) else {
            return Ok(());
        };
        self.history.write_send(
            store,
            conversation_id,
            message_id,
            session.log(),
            session.attempts(),
        )?;
        Ok(())
    }

    /// Save the message and attempt together. Refusal retains this write until
    /// a later call or tail pass can save the current outcome.
    pub fn persist_send(
        &mut self,
        conversation_id: &str,
        message_id: &str,
        deep: bool,
    ) -> Result<(), PersistenceError> {
        let Some(store) = self.persistence.clone() else {
            return Ok(());
        };
        let key = (conversation_id.to_string(), message_id.to_string());
        let deep = *self
            .pending
            .sends
            .entry(key.clone())
            .and_modify(|value| *value |= deep)
            .or_insert(deep);
        self.write_send(&store, conversation_id, message_id, deep)?;
        self.pending.sends.remove(&key);
        Ok(())
    }

    /// Save a newly created record now. A refused placeholder record is also
    /// retained, even before the conversation becomes final.
    pub fn persist_record(
        &mut self,
        conversation_id: &str,
        final_now: bool,
    ) -> Result<(), PersistenceError> {
        let Some(store) = self.persistence.clone() else {
            return Ok(());
        };
        self.pending
            .request_state(conversation_id, final_now, true, final_now);
        self.flush_state(&store, conversation_id)
    }

    fn write_send(
        &mut self,
        store: &Persistence,
        id: &str,
        message: &str,
        deep: bool,
    ) -> Result<(), PersistenceError> {
        let Some(session) = self.sessions.get(id) else {
            return Ok(());
        };
        if !self
            .history
            .write_send(store, id, message, session.log(), session.attempts())?
        {
            return Ok(());
        }
        let record_due = session.record_is_final()
            && (!self.final_records.contains(id) || session.record_changed());
        self.pending
            .request_state(id, deep || record_due, record_due, record_due);
        self.flush_state(store, id)
    }

    fn persist_session_tail(
        &mut self,
        store: &Persistence,
        id: &str,
    ) -> Result<(), PersistenceError> {
        let session = &self.sessions[id];
        let changed = self
            .history
            .write_tail(store, id, session.log(), session.transfer())?;
        let record_due = session.record_is_final()
            && (!self.final_records.contains(id) || session.record_changed());
        self.pending
            .request_state(id, changed || record_due, record_due, record_due);
        self.flush_state(store, id)
    }

    fn flush_state(&mut self, store: &Persistence, id: &str) -> Result<(), PersistenceError> {
        let Some(pending) = self.pending.state.get(id).copied() else {
            return Ok(());
        };
        let Some(session) = self.sessions.get(id) else {
            self.pending.state.remove(id);
            return Ok(());
        };
        if pending.extra {
            session.write_extra(store)?;
            self.pending.state.get_mut(id).expect("pending state").extra = false;
        }
        if pending.record {
            self.history.write_record(store, id, &session.record())?;
            if pending.finalize {
                self.sessions
                    .get_mut(id)
                    .expect("existing session")
                    .record_written();
                self.final_records.insert(id.to_string());
            }
        }
        self.pending.state.remove(id);
        Ok(())
    }
}
