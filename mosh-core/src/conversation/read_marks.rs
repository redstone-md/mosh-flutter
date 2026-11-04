//! What the user has already seen of each conversation on this installation.
//!
//! A mark is two numbers. `floor_ms` is where this installation started
//! counting: just after the newest message the conversation held when the
//! mark was created, or the creation time for an empty one. Anything sent
//! earlier is history it arrived with (an existing chat on upgrade, an
//! archive imported onto a linked device, a channel's backlog) and is never
//! unread. `seen` counts the incoming messages since the floor that the user
//! has had on screen.
//!
//! Counting keeps the count right whatever order messages arrive in. Which
//! messages are the unread ones is read in send order, the order history is
//! replayed in, so the divider sits in the same place before and after a
//! restart. A message recovered after newer ones were seen moves the divider
//! to the newest unread position rather than onto itself.
//!
//! Marks live in the encrypted store, so unread counts survive a restart.
//! An absent mark is created, and saved, the first time it is asked for.

use std::collections::HashMap;

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

use super::message_log::ConversationMessage;
use super::now_ms;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::persistence::{HistoryTables, Persistence};

/// The unread part of a conversation snapshot.
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct UnreadState {
    /// Incoming messages that arrived after the user last viewed it.
    pub count: u32,
    /// The oldest of them by arrival, where the unread divider goes.
    pub first_unread_message_id: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct ReadMark {
    floor_ms: u64,
    seen: u32,
}

impl ReadMark {
    /// A new mark: history already held is read, the rest is not.
    fn starting_after<M: ConversationMessage>(log: &[M]) -> Self {
        let newest = log.iter().filter_map(ConversationMessage::sent_at_ms).max();
        Self {
            floor_ms: newest.map_or_else(now_ms, |sent| sent + 1),
            seen: 0,
        }
    }

    /// The messages that can be unread, in send order: someone else's, sent
    /// since the floor, not a service line or a call log entry. One the user
    /// hid still counts, so hiding a seen message cannot hide the next one.
    /// A message is own when its record says so or its author is the
    /// installation's own; recovered group records never claim ownership.
    fn incoming<'a, M: ConversationMessage>(&self, log: &'a [M], own_author: &str) -> Vec<&'a M> {
        let mut incoming: Vec<&M> = log
            .iter()
            .filter(|message| {
                let own = message.metadata().and_then(|m| m.is_own) == Some(true)
                    || message.author() == own_author;
                !own && !message.is_service()
                    && message.call_id().is_none()
                    && message.sent_at_ms().unwrap_or(self.floor_ms) >= self.floor_ms
            })
            .collect();
        incoming.sort_by_key(|message| (message.sent_at_ms(), message.message_id()));
        incoming
    }

    fn state<M: ConversationMessage>(&self, log: &[M], own_author: &str) -> UnreadState {
        let incoming = self.incoming(log, own_author);
        let seen = (self.seen as usize).min(incoming.len());
        UnreadState {
            count: (incoming.len() - seen) as u32,
            first_unread_message_id: incoming
                .get(seen)
                .and_then(|message| message.message_id())
                .map(str::to_string),
        }
    }
}

/// The marks of one conversation kind, read from the store once each.
pub(crate) struct ReadMarks {
    tables: HistoryTables,
    marks: HashMap<String, ReadMark>,
}

impl ReadMarks {
    pub(crate) fn new(tables: HistoryTables) -> Self {
        Self {
            tables,
            marks: HashMap::new(),
        }
    }

    pub(crate) fn state<M: ConversationMessage>(
        &mut self,
        store: Option<&Persistence>,
        id: &str,
        log: &[M],
        own_author: &str,
    ) -> UnreadState {
        self.mark(store, id, log).state(log, own_author)
    }

    /// Everything incoming is now seen. Saved only when that changes.
    pub(crate) fn mark_read<M: ConversationMessage>(
        &mut self,
        store: Option<&Persistence>,
        id: &str,
        log: &[M],
        own_author: &str,
    ) {
        let mark = self.mark(store, id, log);
        let seen = mark.incoming(log, own_author).len() as u32;
        if seen != mark.seen {
            self.save(store, id, ReadMark { seen, ..mark });
        }
    }

    pub(crate) fn forget(&mut self, id: &str) {
        self.marks.remove(id);
    }

    /// The stored mark, or a new one saved now. A store that cannot be read
    /// gets a mark for this answer only, so a passing fault never replaces
    /// what is on disk.
    fn mark<M: ConversationMessage>(
        &mut self,
        store: Option<&Persistence>,
        id: &str,
        log: &[M],
    ) -> ReadMark {
        if let Some(mark) = self.marks.get(id) {
            return *mark;
        }
        match store.map(|store| self.load(store, id)).transpose() {
            Ok(Some(Some(mark))) => {
                self.marks.insert(id.to_string(), mark);
                mark
            }
            Ok(_) => {
                let mark = ReadMark::starting_after(log);
                self.save(store, id, mark);
                mark
            }
            Err(()) => ReadMark::starting_after(log),
        }
    }

    fn load(&self, store: &Persistence, id: &str) -> Result<Option<ReadMark>, ()> {
        let Some(bytes) = store
            .get_read_mark(self.tables, id)
            .map_err(|error| self.log("read", &error))?
        else {
            return Ok(None);
        };
        serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|error| self.log("decode", &error))
    }

    /// Keeps the mark in memory even when the write is refused, so the badge
    /// stays right for this run; the next change retries the write.
    fn save(&mut self, store: Option<&Persistence>, id: &str, mark: ReadMark) {
        self.marks.insert(id.to_string(), mark);
        let Some(store) = store else { return };
        let written = serde_json::to_vec(&mark)
            .map_err(|error| error.to_string())
            .and_then(|bytes| {
                store
                    .put_read_mark(self.tables, id, &bytes)
                    .map_err(|error| error.to_string())
            });
        if let Err(error) = written {
            self.log("write", &error);
        }
    }

    fn log(&self, action: &str, error: &dyn std::fmt::Display) {
        dlog::write(
            LogLevel::Warn,
            kinds::PERSIST,
            self.tables.label,
            &format!("read mark {action} failed: {error}"),
        );
    }
}
