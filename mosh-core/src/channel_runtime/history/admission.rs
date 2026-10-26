//! Preserve local state and legacy aliases while comparing immutable semantics.
use super::*;
use crate::conversation::history::StoredMessage;

use crate::conversation::recovery::occurrence::Occurrence;

impl ChannelSession {
    pub(super) fn history_row_for(
        &self,
        record: ChannelRecord,
        holder: &str,
    ) -> Result<StoredMessage<ChannelMessage>, ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        let indexed = store.history_occurrence(CHANNEL_HISTORY, &self.name, &record.message_id)?;
        validate_index(&record, indexed.as_ref())?;
        let deletion = self.history_erasure(&record, holder)?;
        if let Some(existing) = self.held_history_row(&record, indexed.as_ref())? {
            if let Some(previous) = ChannelRecord::from_stored(&existing)
                .filter(|_| !matches!(record.content, records::Content::Erased { .. }))
            {
                if previous
                    .semantic_digest()
                    .map_err(ChannelRuntimeError::Codec)?
                    != record
                        .semantic_digest()
                        .map_err(ChannelRuntimeError::Codec)?
                {
                    return Err(ChannelRuntimeError::Codec(
                        "conflicting history occurrence".into(),
                    ));
                }
            }
            return Ok(existing);
        }
        let mut row = imported_row(&self.name, record, holder, deletion);
        self.set_verified_ownership(&mut row.message)?;
        Ok(row)
    }

    fn history_erasure(
        &self,
        record: &ChannelRecord,
        holder: &str,
    ) -> Result<Option<crate::message_deletion::DeletionRecord>, ChannelRuntimeError> {
        let records::Content::Erased { deletion_key, .. } = &record.content else {
            return Ok(None);
        };
        let authority = self.deletion_authority()?;
        self.deletions
            .records
            .values()
            .find(|r| {
                r.key == *deletion_key
                    && r.scope == crate::message_deletion::DeleteScope::ForEveryone
                    && r.request
                        .as_ref()
                        .is_some_and(|q| Some(&q.target) == record.origin.as_ref())
                    && authority.validate(r, holder).is_ok()
            })
            .cloned()
            .map(Some)
            .ok_or_else(|| {
                ChannelRuntimeError::Codec("erased target awaits verified deletion".into())
            })
    }

    fn held_history_row(
        &self,
        record: &ChannelRecord,
        indexed: Option<&Occurrence>,
    ) -> Result<Option<StoredMessage<ChannelMessage>>, ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        if let Some(indexed) = indexed {
            return Ok(store.history_row(CHANNEL_HISTORY, &indexed.row_key)?);
        }
        let Some(message) = self
            .messages
            .iter()
            .find(|m| m.message_id.as_ref() == Some(&record.message_id))
        else {
            return Ok(None);
        };
        Ok(store.history_message(
            CHANNEL_HISTORY,
            &self.name,
            &crate::conversation::recovery::manifest::HistoryKey {
                message_id: record.message_id.clone(),
                sent_at_ms: message.sent_at_ms.unwrap_or_default(),
                digest: String::new(),
            },
        )?)
    }
}

fn validate_index(
    record: &ChannelRecord,
    indexed: Option<&Occurrence>,
) -> Result<(), ChannelRuntimeError> {
    let Some(indexed) = indexed else {
        return Ok(());
    };
    let identity = record
        .origin
        .as_ref()
        .map(|origin| origin.key())
        .transpose()
        .map_err(ChannelRuntimeError::Codec)?;
    let identity = identity.unwrap_or(format!(
        "legacy-{}",
        record
            .semantic_digest()
            .map_err(ChannelRuntimeError::Codec)?
    ));
    if identity != indexed.identity
        || (!matches!(record.content, records::Content::Erased { .. })
            && indexed
                .content_digest
                .as_ref()
                .is_some_and(|digest| record.semantic_digest().ok().as_ref() != Some(digest)))
    {
        return Err(ChannelRuntimeError::Codec(
            "conflicting history occurrence".into(),
        ));
    }
    Ok(())
}

fn imported_row(
    name: &str,
    record: ChannelRecord,
    holder: &str,
    deletion: Option<crate::message_deletion::DeletionRecord>,
) -> StoredMessage<ChannelMessage> {
    use crate::conversation::recovery::{HistoryClassification, HistoryEvidence};
    let classification = if record.origin.is_some() {
        HistoryClassification::OriginalOrigin
    } else {
        HistoryClassification::LegacyUnsigned
    };
    let absent = record.legacy_id_absent;
    let mut row = record.row(name);
    if let Some(deletion) = deletion {
        let metadata = row.message.metadata.as_mut().unwrap();
        metadata.deletion_key = Some(deletion.key);
        metadata.deletion = Some(crate::message_deletion::DeletionMarker {
            scope: deletion.scope,
            status: deletion.status,
            administrator: deletion.administrator,
        });
    }
    row.history_evidence = Some(HistoryEvidence {
        holder_key: holder.into(),
        classification,
        legacy_original_id_absent: absent,
        group: None,
    });
    row
}
