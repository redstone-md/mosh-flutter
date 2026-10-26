//! Preserve local state and legacy aliases while comparing immutable semantics.
use super::*;
use crate::conversation::history::StoredMessage;

impl ChannelSession {
    pub(super) fn history_row_for(
        &self,
        record: ChannelRecord,
        holder: &str,
    ) -> Result<StoredMessage<ChannelMessage>, ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        let indexed = store.history_occurrence(CHANNEL_HISTORY, &self.name, &record.message_id)?;
        let erased = matches!(record.content, records::Content::Erased { .. });
        if let Some(indexed) = &indexed {
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
                || (!erased
                    && indexed.content_digest.as_ref().is_some_and(|digest| {
                        record.semantic_digest().ok().as_ref() != Some(digest)
                    }))
            {
                return Err(ChannelRuntimeError::Codec(
                    "conflicting history occurrence".into(),
                ));
            }
        }
        let deletion = if let records::Content::Erased { deletion_key, .. } = &record.content {
            let authority = self.deletion_authority()?;
            Some(
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
                    .ok_or_else(|| {
                        ChannelRuntimeError::Codec("erased target awaits verified deletion".into())
                    })?,
            )
        } else {
            None
        };
        let existing = if let Some(indexed) = &indexed {
            store.history_row::<ChannelMessage>(CHANNEL_HISTORY, &indexed.row_key)?
        } else if let Some(message) = self
            .messages
            .iter()
            .find(|m| m.message_id.as_ref() == Some(&record.message_id))
        {
            store.history_message(
                CHANNEL_HISTORY,
                &self.name,
                &crate::conversation::recovery::manifest::HistoryKey {
                    message_id: record.message_id.clone(),
                    sent_at_ms: message.sent_at_ms.unwrap_or_default(),
                    digest: String::new(),
                },
            )?
        } else {
            None
        };
        if let Some(existing) = existing {
            if let Some(previous) = ChannelRecord::from_stored(&existing).filter(|_| !erased) {
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
        let classification = if record.origin.is_some() {
            crate::conversation::recovery::HistoryClassification::OriginalOrigin
        } else {
            crate::conversation::recovery::HistoryClassification::LegacyUnsigned
        };
        let absent = record.legacy_id_absent;
        let mut row = record.row(&self.name);
        if let Some(deletion) = deletion {
            let metadata = row.message.metadata.as_mut().unwrap();
            metadata.deletion_key = Some(deletion.key);
            metadata.deletion = Some(crate::message_deletion::DeletionMarker {
                scope: deletion.scope,
                status: deletion.status,
                administrator: deletion.administrator,
            });
        }
        row.history_evidence = Some(crate::conversation::recovery::HistoryEvidence {
            holder_key: holder.into(),
            classification,
            legacy_original_id_absent: absent,
            group: None,
        });
        Ok(row)
    }
}
