//! Bounded serialization of the frozen source view; no whole-history clone.
use super::*;
use crate::conversation::recovery::{cursor::PAGE_RECORDS, manifest::FrozenKey};
use crate::message_deletion::protocol::DeletionMessage;

impl ChannelSession {
    pub(super) fn history_journal_page(
        &self,
        prefix: &str,
        pull: &HistoryPull,
    ) -> Result<HistoryMessage<ChannelRecord>, ChannelRuntimeError> {
        let (records, next) = self.deletions.store.as_ref().unwrap().recovery_page(
            &format!("{prefix}\u{1}journal\u{1}"),
            pull.journal_after.as_deref(),
        )?;
        let page = DeletionMessage::State { records, next };
        let bytes =
            serde_json::to_vec(&page).map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?;
        let page = if bytes.len() > 24_000 {
            DeletionMessage::Fragment(
                crate::conversation::recovery::fragment::fragment(&bytes, pull.fragment_offset)
                    .map_err(ChannelRuntimeError::Codec)?,
            )
        } else if pull.fragment_offset == 0 {
            page
        } else {
            return Err(ChannelRuntimeError::Codec(
                "unexpected journal fragment offset".into(),
            ));
        };
        Ok(HistoryMessage::Journal {
            manifest: pull.manifest.clone(),
            deletion_digest: pull.deletion_digest.clone(),
            page,
        })
    }

    pub(super) fn history_content_page(
        &self,
        prefix: &str,
        total: usize,
        pull: &HistoryPull,
    ) -> Result<HistoryMessage<ChannelRecord>, ChannelRuntimeError> {
        let mut records = Vec::new();
        let mut bytes = 0;
        let mut fragment = None;
        for index in pull.offset..total.min(pull.offset.saturating_add(PAGE_RECORDS)) {
            let record = self.frozen_history_record(prefix, index)?;
            let serialized = serde_json::to_vec(&record)
                .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?;
            if bytes + serialized.len() > 24_000 {
                if records.is_empty() {
                    fragment = Some(
                        crate::conversation::recovery::fragment::fragment(
                            &serialized,
                            pull.fragment_offset,
                        )
                        .map_err(ChannelRuntimeError::Codec)?,
                    );
                }
                break;
            }
            if pull.fragment_offset != 0
                && !matches!(record.content, records::Content::Erased { .. })
            {
                return Err(ChannelRuntimeError::Codec(
                    "unexpected history fragment offset".into(),
                ));
            }
            bytes += serialized.len();
            records.push(record);
        }
        Ok(HistoryMessage::Page {
            manifest: pull.manifest.clone(),
            total,
            offset: pull.offset,
            records,
            fragment,
        })
    }

    fn frozen_history_record(
        &self,
        prefix: &str,
        index: usize,
    ) -> Result<ChannelRecord, ChannelRuntimeError> {
        let store = self.deletions.store.as_ref().unwrap();
        let key = store
            .recovery_state::<FrozenKey>(&format!("{prefix}\u{1}keys\u{1}{index:020}"))?
            .ok_or_else(|| ChannelRuntimeError::Codec("frozen history key missing".into()))?;
        let row = store
            .history_row::<ChannelMessage>(CHANNEL_HISTORY, &key.row_key)?
            .ok_or_else(|| ChannelRuntimeError::Codec("history row unavailable".into()))?;
        let record = match ChannelRecord::from_stored(&row) {
            Some(record) => record,
            None => self.erased_history_record(&row, &key.key.digest)?,
        };
        if record
            .binding_digest()
            .map_err(ChannelRuntimeError::Codec)?
            != key.key.digest
        {
            return Err(ChannelRuntimeError::Codec(
                "frozen history record changed".into(),
            ));
        }
        Ok(record)
    }
}
