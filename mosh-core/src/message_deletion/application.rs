use super::{DeleteScope, DeletionContext, DeletionRecord, DeletionStatus};
use crate::conversation::{history::StoredMessage, message_log::ConversationMessage};
use std::collections::{BTreeMap, HashSet};

struct Erasure<M> {
    index: usize,
    message: M,
    row: StoredMessage<M>,
}

impl<M: ConversationMessage> Erasure<M> {
    fn new(index: usize, message: M, context: &str) -> Self {
        let row = StoredMessage {
            conversation_id: context.split_once(':').map_or(context, |(_, id)| id).into(),
            sent_at_ms: message.sent_at_ms().unwrap_or_default(),
            message_id: message.message_id().unwrap_or_default().into(),
            message: message.clone(),
            attachment_manifest: None,
        };
        Self {
            index,
            message,
            row,
        }
    }
}

struct ErasurePlan<M> {
    merged: BTreeMap<String, DeletionRecord>,
    changes: Vec<Erasure<M>>,
    cancelled: HashSet<String>,
    attachments: Vec<crate::conversation::attachments::AttachmentDescriptor>,
}

pub(crate) fn apply<M: ConversationMessage>(
    context: &mut DeletionContext<'_, M>,
) -> Result<(), String> {
    if let Some(store) = &context.book.store {
        context.transfer.collect_erased_cache(store);
    }
    context.book.reload()?;
    if context.book.records.is_empty() {
        return Ok(());
    }
    let user = context.book.user().map_err(|e| e.to_string())?;
    let records = context
        .book
        .records
        .values()
        .filter(|r| r.owner == user || r.scope == DeleteScope::ForEveryone)
        .cloned()
        .collect::<Vec<_>>();
    install(context, &records, false)
}

pub(super) fn install<M: ConversationMessage>(
    context: &mut DeletionContext<'_, M>,
    records: &[DeletionRecord],
    accepted: bool,
) -> Result<(), String> {
    let mut plan = ErasurePlan::new(context, records)?;
    if plan.unchanged(context, records, accepted) {
        return Ok(());
    }
    if let Some(store) = &context.book.store {
        let rows = plan.changes.iter().map(|c| &c.row).collect::<Vec<_>>();
        let markers = store
            .commit_message_deletions(
                context.book.tables,
                records,
                &rows,
                &plan.cancelled,
                &plan.attachments,
                accepted,
            )
            .map_err(|e| e.to_string())?;
        for change in &mut plan.changes {
            if let Some(marker) = markers.get(&change.row.message_id) {
                change.message.metadata_mut().as_mut().unwrap().deletion = Some(marker.clone());
            }
        }
    }
    if accepted {
        for record in records
            .iter()
            .filter(|r| r.status == DeletionStatus::Confirmed && r.acknowledgement.is_some())
        {
            context
                .book
                .accepted
                .insert(record.request.as_ref().ok_or("missing request")?.digest()?);
        }
    }
    plan.apply(context);
    Ok(())
}

impl<M: ConversationMessage> ErasurePlan<M> {
    fn unchanged(
        &self,
        context: &DeletionContext<'_, M>,
        records: &[DeletionRecord],
        accepted: bool,
    ) -> bool {
        self.changes.is_empty()
            && records.iter().all(|r| {
                self.merged.get(&r.storage_key()) == context.book.records.get(&r.storage_key())
            })
            && (!accepted
                || records
                    .iter()
                    .filter(|r| r.status == DeletionStatus::Confirmed)
                    .all(|r| {
                        r.request
                            .as_ref()
                            .and_then(|q| q.digest().ok())
                            .is_some_and(|d| context.book.accepted.contains(&d))
                    }))
    }
    fn new(context: &DeletionContext<'_, M>, records: &[DeletionRecord]) -> Result<Self, String> {
        let mut merged = context.book.records.clone();
        for record in records {
            let key = record.storage_key();
            let next = merged
                .get(&key)
                .map_or_else(|| record.clone(), |old| old.merged(record));
            merged.insert(key, next);
        }
        let owner = context.book.user().map_err(|e| e.to_string())?;
        let relevant = merged
            .values()
            .filter(|r| r.scope == DeleteScope::ForEveryone || r.owner == owner)
            .cloned()
            .collect::<Vec<_>>();
        let changes = prepare(context, &relevant)?;
        let cancelled = changes
            .iter()
            .filter(|c| {
                c.message
                    .metadata()
                    .and_then(|m| m.deletion.as_ref())
                    .is_some_and(|d| d.scope == DeleteScope::ForEveryone)
                    || context
                        .attempts
                        .get(&c.row.message_id)
                        .is_none_or(|a| a.ever_published == Some(false))
            })
            .map(|c| c.row.message_id.clone())
            .collect();
        let attachments = changes
            .iter()
            .filter_map(|c| context.log[c.index].attachment().cloned())
            .collect();
        Ok(Self {
            merged,
            changes,
            cancelled,
            attachments,
        })
    }

    fn apply(self, context: &mut DeletionContext<'_, M>) {
        context.book.records = self.merged;
        for change in self.changes {
            if self.cancelled.contains(&change.row.message_id) {
                context.attempts.remove(&change.row.message_id);
            }
            context.log.replace(change.index, change.message);
        }
        for attachment in self.attachments {
            if !context.log.iter().any(|m| {
                m.attachment()
                    .is_some_and(|a| a.attachment_id == attachment.attachment_id)
            }) {
                context.transfer.forget(&attachment.attachment_id);
            }
            if let Err(error) = context
                .transfer
                .clean_erased(&attachment, context.book.store.as_deref())
            {
                crate::diagnostics_log::write(
                    crate::diagnostics_log::LogLevel::Warn,
                    crate::diagnostics_log::kinds::PERSIST,
                    &context.book.context,
                    &format!("attachment cleanup deferred: {error}"),
                );
            }
        }
    }
}

fn prepare<M: ConversationMessage>(
    context: &DeletionContext<'_, M>,
    records: &[DeletionRecord],
) -> Result<Vec<Erasure<M>>, String> {
    let mut changes = Vec::new();
    for (index, original) in context.log.iter().enumerate() {
        let (key, local_only) =
            super::target::target(&context.book.context, original, context.transfer)?;
        let correlation =
            super::correlation::message_key(&context.book.context, original, context.transfer)?;
        let Some(record) = records
            .iter()
            .filter(|r| r.matches(&key, correlation.as_deref()))
            .max_by_key(|r| {
                (
                    r.scope == DeleteScope::ForMe || r.status == DeletionStatus::Rejected,
                    r.status == DeletionStatus::Confirmed,
                    r.storage_key(),
                )
            })
        else {
            continue;
        };
        let marker = record.marker();
        if original.metadata().and_then(|m| m.deletion.as_ref()) == Some(&marker) {
            continue;
        }
        let mut message = original.clone();
        let metadata = message.metadata_mut().get_or_insert_with(Default::default);
        metadata.personal_correlation = correlation.filter(|alias| alias != &key);
        metadata.deletion_key = Some(key);
        metadata.local_only = local_only;
        metadata.deletion = Some(marker);
        metadata.can_delete_for_everyone = false;
        message.erase_content();
        changes.push(Erasure::new(index, message, &context.book.context));
    }
    Ok(changes)
}
