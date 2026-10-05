use super::{DeleteScope, DeletionBook, DeletionRecord, DeletionStatus};
use crate::conversation::{
    history::StoredMessage,
    message_log::{ConversationMessage, MessageLog},
    transfer::Transfer,
};
use crate::outbound_delivery::OutboundAttemptRecord;
use std::collections::HashSet;
struct Erasure<M> {
    index: usize,
    message: M,
    row: StoredMessage<M>,
}

impl DeletionBook {
    fn prepare<M: ConversationMessage>(
        &self,
        log: &MessageLog<M>,
        transfer: &Transfer,
        records: &[DeletionRecord],
    ) -> Result<Vec<Erasure<M>>, String> {
        let mut changes = Vec::new();
        for (index, original) in log.iter().enumerate() {
            let (key, local_only) = super::target::target(&self.context, original, transfer)?;
            let record = records.iter().filter(|r| r.key == key).max_by_key(|r| {
                (
                    r.scope == DeleteScope::ForMe || r.status == DeletionStatus::Rejected,
                    r.status == DeletionStatus::Confirmed,
                    r.storage_key(),
                )
            });
            let Some(record) = record else {
                continue;
            };
            let marker = record.marker();
            if original.metadata().and_then(|m| m.deletion.as_ref()) == Some(&marker) {
                continue;
            }
            let mut message = original.clone();
            let metadata = message.metadata_mut().get_or_insert_with(Default::default);
            metadata.deletion_key = Some(key);
            metadata.local_only = local_only;
            metadata.deletion = Some(marker);
            metadata.can_delete_for_everyone = false;
            message.erase_content();
            let row = StoredMessage {
                conversation_id: self.conversation_id().into(),
                sent_at_ms: message.sent_at_ms().unwrap_or_default(),
                message_id: message.message_id().unwrap_or_default().into(),
                message: message.clone(),
                attachment_manifest: None,
            };
            changes.push(Erasure {
                index,
                message,
                row,
            });
        }
        Ok(changes)
    }

    fn conversation_id(&self) -> &str {
        self.context
            .split_once(':')
            .map_or(self.context.as_str(), |(_, id)| id)
    }

    pub(super) fn install<M: ConversationMessage>(
        &mut self,
        log: &mut MessageLog<M>,
        attempts: &mut std::collections::HashMap<String, OutboundAttemptRecord>,
        transfer: &mut Transfer,
        records: &[DeletionRecord],
    ) -> Result<(), String> {
        let mut merged = self.records.clone();
        for record in records {
            let key = record.storage_key();
            let next = merged
                .get(&key)
                .map_or_else(|| record.clone(), |old| old.merged(record));
            merged.insert(key, next);
        }
        let owner = self.user()?;
        let relevant: Vec<_> = merged
            .values()
            .filter(|r| r.scope == DeleteScope::ForEveryone || r.owner == owner)
            .cloned()
            .collect();
        let changes = self.prepare(log, transfer, &relevant)?;
        if changes.is_empty()
            && records
                .iter()
                .all(|r| self.records.get(&r.storage_key()) == Some(r))
        {
            return Ok(());
        }
        let cancelled: HashSet<_> = changes
            .iter()
            .filter(|c| {
                c.message
                    .metadata()
                    .and_then(|m| m.deletion.as_ref())
                    .is_some_and(|d| d.scope == DeleteScope::ForEveryone)
                    || attempts
                        .get(&c.row.message_id)
                        .is_none_or(|a| a.ever_published == Some(false))
            })
            .map(|c| c.row.message_id.clone())
            .collect();
        let saved: Vec<_> = records
            .iter()
            .filter_map(|r| merged.get(&r.storage_key()).cloned())
            .collect();
        let attachments: Vec<_> = changes
            .iter()
            .filter_map(|c| log[c.index].attachment().cloned())
            .collect();
        if let Some(store) = &self.store {
            let rows: Vec<_> = changes.iter().map(|c| &c.row).collect();
            store
                .commit_message_deletions(self.tables, &saved, &rows, &cancelled, &attachments)
                .map_err(|e| e.to_string())?;
        }
        self.records = merged;
        for change in changes {
            if cancelled.contains(&change.row.message_id) {
                attempts.remove(&change.row.message_id);
            }
            log.replace(change.index, change.message);
        }
        for attachment in attachments {
            if !log.iter().any(|m| {
                m.attachment()
                    .is_some_and(|a| a.attachment_id == attachment.attachment_id)
            }) {
                transfer.forget(&attachment.attachment_id);
            }
            if let Err(error) = transfer.clean_erased(&attachment, self.store.as_deref()) {
                crate::diagnostics_log::write(
                    crate::diagnostics_log::LogLevel::Warn,
                    crate::diagnostics_log::kinds::PERSIST,
                    &self.context,
                    &format!("attachment cleanup deferred: {error}"),
                );
            }
        }
        Ok(())
    }
}
