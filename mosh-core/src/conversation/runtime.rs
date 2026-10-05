//! The shell every conversation runtime is.
//!
//! Underneath the three kinds there is one machine: a table of conversations
//! by id, the room each of them opens on the shared node, and the writes that
//! keep them on disk. Each kind wrote that machine out for itself, and the
//! copies drifted — the channel rewrote its record on every poll, the DM and
//! the group had two spellings of the same "is this record worth saving yet"
//! rule.
//!
//! It is written once here, and the kind supplies its id, messages, unsettled
//! sends, attachment transfer, rebuild record, and any extra durable state —
//! an MLS snapshot for a DM and a group, nothing for a public channel.
//!
//! What stays with the kind: everything about the wire. Who may speak, what an
//! envelope looks like, how a frame is published, when a session is ready.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use serde::de::DeserializeOwned;
use serde::Serialize;

#[path = "runtime_writes.rs"]
mod writes;

use super::history::{History, Restore};
use super::message_log::{ConversationMessage, MessageLog};
use super::transfer::Transfer;
use crate::attachment_store::AttachmentStore;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::moss_ffi::MossNode;
use crate::outbound_delivery::OutboundAttemptRecord;
use crate::persistence::{HistoryTables, Persistence, PersistenceError};
use crate::shared_node::SharedMossNode;

/// What the shell needs from one conversation, whatever kind it is.
pub trait ConversationSession {
    fn attach_persistence(&mut self, _store: Option<Arc<Persistence>>) {}
    /// The message this kind keeps a log of.
    type Message: ConversationMessage + DeserializeOwned;
    /// What this conversation is rebuilt from at startup.
    type Record: Serialize;

    /// The id this conversation is filed under: a session id, a group id, a
    /// channel name.
    fn conversation_id(&self) -> &str;

    fn log(&self) -> &MessageLog<Self::Message>;

    fn transfer(&self) -> Option<&Transfer> {
        None
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord>;

    fn record(&self) -> Self::Record;

    /// Durable state of this kind that goes down beside the history. A DM and
    /// a group save their MLS snapshot here; a public channel has none.
    fn write_extra(&self, _persistence: &Persistence) -> Result<(), PersistenceError> {
        Ok(())
    }

    /// Whether the record is worth saving yet. A joiner's record carries an
    /// empty MLS group id until the Welcome lands, and a conversation saved
    /// in that state cannot be rebuilt. A kind with nothing to wait for is
    /// final from the start.
    fn record_is_final(&self) -> bool {
        true
    }

    /// Whether a saved field has changed since the record was last written.
    /// Only a DM has one — the counterpart's moss peer id can arrive, or
    /// change on a re-handshake, long after the record was first saved.
    fn record_changed(&self) -> bool {
        false
    }

    /// Called once the record has been written, so a kind that tracks changes
    /// can forget the one it just saved.
    fn record_written(&mut self) {}
}

/// The conversations of one kind, and what they have on disk.
pub struct ConversationRuntime<S: ConversationSession> {
    attachment_store: Arc<AttachmentStore>,
    persistence: Option<Arc<Persistence>>,
    history: History,
    /// Conversations whose saved record is already final, so the tail write
    /// refreshes each one only once.
    final_records: HashSet<String>,
    sessions: HashMap<String, S>,
    pending: writes::PendingWrites,
}

impl<S: ConversationSession> ConversationRuntime<S> {
    pub fn new(
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
        tables: HistoryTables,
    ) -> Self {
        Self {
            attachment_store,
            persistence,
            history: History::new(tables),
            final_records: HashSet::new(),
            sessions: HashMap::new(),
            pending: writes::PendingWrites::default(),
        }
    }

    /// The store every conversation of this kind keeps its files in. Each one
    /// builds its own transfer over it.
    pub fn attachment_store(&self) -> &Arc<AttachmentStore> {
        &self.attachment_store
    }

    pub fn persistence(&self) -> Option<&Arc<Persistence>> {
        self.persistence.as_ref()
    }

    pub fn get(&self, conversation_id: &str) -> Option<&S> {
        self.sessions.get(conversation_id)
    }

    pub fn get_mut(&mut self, conversation_id: &str) -> Option<&mut S> {
        self.sessions.get_mut(conversation_id)
    }

    pub fn holds(&self, conversation_id: &str) -> bool {
        self.sessions.contains_key(conversation_id)
    }

    pub fn insert(&mut self, conversation_id: String, mut session: S) {
        session.attach_persistence(self.persistence.clone());
        self.sessions.insert(conversation_id, session);
    }

    /// Takes a conversation out of the table. Forgetting what is on disk is a
    /// separate step, because leaving a conversation and closing the app are
    /// not the same thing.
    pub fn remove(&mut self, conversation_id: &str) -> Option<S> {
        self.sessions.remove(conversation_id)
    }

    pub fn values(&self) -> impl Iterator<Item = &S> {
        self.sessions.values()
    }

    pub fn values_mut(&mut self) -> impl Iterator<Item = &mut S> {
        self.sessions.values_mut()
    }

    pub fn iter_mut(&mut self) -> impl Iterator<Item = (&String, &mut S)> {
        self.sessions.iter_mut()
    }

    /// The record of every conversation of this kind saved last time.
    pub fn stored_records<R: DeserializeOwned>(&self) -> Vec<R> {
        match self.persistence.as_ref() {
            Some(persistence) => self.history.stored_conversations(persistence),
            None => Vec::new(),
        }
    }

    /// Reads one conversation's messages, unsettled sends and cached
    /// attachments back in. Called while the session is still being built, so
    /// it takes the places to fill rather than an id.
    pub fn replay(&mut self, conversation_id: &str, into: Restore<'_, S::Message>) {
        let Some(persistence) = self.persistence.as_ref().cloned() else {
            return;
        };
        self.history.replay(&persistence, conversation_id, into);
    }

    /// Says the current record is already durably saved. Creation marks it
    /// after accepting its atomic pair; rehydrate marks restored records.
    /// The next unchanged tail need not re-encrypt the conversation state.
    pub fn mark_record_final(&mut self, conversation_id: &str) {
        self.final_records.insert(conversation_id.to_string());
    }

    /// Forgets what the shell remembers about one conversation: how much of
    /// its history is already down, and whether its record is final. For one
    /// the user left, whose rows are being deleted anyway.
    pub fn forget(&mut self, conversation_id: &str) {
        self.history.forget(conversation_id);
        self.final_records.remove(conversation_id);
        self.pending.forget(conversation_id);
    }
}

/// Reaching for a conversation by id, the way a map does. Panics on one that
/// is not open — [`ConversationRuntime::get`] is the answer everywhere the
/// conversation may genuinely be gone.
impl<S: ConversationSession> std::ops::Index<&str> for ConversationRuntime<S> {
    type Output = S;

    fn index(&self, conversation_id: &str) -> &S {
        &self.sessions[conversation_id]
    }
}

/// Puts one conversation's room on the shared node and subscribes its channels
/// there. Rolls the reference back if the room work fails, so a conversation
/// that never opened cannot pin the node up forever.
///
/// Wire-identical to what a node owning that room published before, so a
/// consolidated client still talks to every already-released one.
pub fn open_room(
    shared_node: &SharedMossNode,
    mesh_id: &str,
    channels: &[String],
    listen_port: u16,
    static_peer: Option<String>,
) -> Result<Arc<MossNode>, String> {
    let node = shared_node
        .acquire(listen_port, static_peer)
        .map_err(|error| error.to_string())?;
    if let Err(error) = join_room(&node, mesh_id, channels) {
        shared_node.release();
        return Err(error);
    }
    Ok(node)
}

/// The inverse of [`open_room`]. Unsubscribe first, then forget the key:
/// leaving first would strand subscriptions that can no longer resolve.
///
/// On a shared node this has to be said out loud. Dropping the session no
/// longer ends its subscriptions — the node lives on for every other
/// conversation, so one that was left would keep receiving.
pub fn close_room(
    shared_node: &SharedMossNode,
    node: &MossNode,
    mesh_id: &str,
    channels: &[String],
    label: &str,
) {
    for channel in channels {
        if let Err(error) = node.unsubscribe_room(mesh_id, channel) {
            dlog::write(
                LogLevel::Warn,
                kinds::ROOM,
                label,
                &format!("could not unsubscribe {channel}: {error}"),
            );
        }
    }
    if let Err(error) = node.leave_room(mesh_id) {
        dlog::write(
            LogLevel::Warn,
            kinds::ROOM,
            label,
            &format!("could not leave its room: {error}"),
        );
    }
    shared_node.release();
}

fn join_room(node: &MossNode, mesh_id: &str, channels: &[String]) -> Result<(), String> {
    node.join_room(mesh_id).map_err(|error| error.to_string())?;
    for channel in channels {
        node.subscribe_room(mesh_id, channel)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "runtime_tests.rs"]
mod tests;
