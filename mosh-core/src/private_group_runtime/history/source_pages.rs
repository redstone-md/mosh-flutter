//! Serialize bounded frozen records; large proofs use the shared fragment protocol.
use super::*;
use super::{protocol::GroupScope, records::GroupRecord};
use crate::conversation::recovery::{
    cursor::PAGE_RECORDS,
    manifest::FrozenKey,
    wire::{HistoryMessage, HistoryPull},
};
use crate::message_deletion::protocol::DeletionMessage;

impl GroupSession {
    pub(super) fn history_journal_page(
        &self,
        prefix: &str,
        pull: &HistoryPull,
    ) -> Result<HistoryMessage<GroupRecord>, PrivateGroupError> {
        let (records, next) = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?
            .recovery_page(
                &format!("{prefix}\u{1}journal\u{1}"),
                pull.journal_after.as_deref(),
            )?;
        let page = DeletionMessage::State { records, next };
        let bytes =
            serde_json::to_vec(&page).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
        let page = if bytes.len() > 8_000 {
            DeletionMessage::Fragment(
                crate::conversation::recovery::fragment::fragment(&bytes, pull.fragment_offset)
                    .map_err(PrivateGroupError::Codec)?,
            )
        } else if pull.fragment_offset == 0 {
            page
        } else {
            return Err(PrivateGroupError::Codec(
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
        &mut self,
        prefix: &str,
        total: usize,
        pull: &HistoryPull,
        recipient: &GroupScope,
        peer: &str,
    ) -> Result<HistoryMessage<GroupRecord>, PrivateGroupError> {
        let mut records = Vec::new();
        let mut bytes = 0;
        let mut fragment = None;
        for index in pull.offset..total.min(pull.offset.saturating_add(PAGE_RECORDS)) {
            let record = self.frozen_history_record(prefix, index, recipient, peer)?;
            let serialized =
                serde_json::to_vec(&record).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
            if bytes + serialized.len() > 8_000 {
                if records.is_empty() {
                    fragment = Some(
                        crate::conversation::recovery::fragment::fragment(
                            &serialized,
                            pull.fragment_offset,
                        )
                        .map_err(PrivateGroupError::Codec)?,
                    );
                }
                break;
            }
            if pull.fragment_offset != 0 {
                return Err(PrivateGroupError::Codec(
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
        &mut self,
        prefix: &str,
        index: usize,
        recipient: &GroupScope,
        peer: &str,
    ) -> Result<GroupRecord, PrivateGroupError> {
        let store = self
            .persistence
            .as_ref()
            .ok_or(PrivateGroupError::NotReady)?;
        let key = store
            .recovery_state::<FrozenKey>(&format!("{prefix}\u{1}keys\u{1}{index:020}"))?
            .ok_or_else(|| PrivateGroupError::Codec("frozen group history key missing".into()))?;
        let row = store
            .history_row::<GroupMessage>(GROUP_HISTORY, &key.row_key)?
            .ok_or_else(|| PrivateGroupError::Codec("group history row unavailable".into()))?;
        if GroupRecord::key(&row, &self.deletions.context, &self.mesh_id)
            .map_err(PrivateGroupError::Codec)?
            .is_none_or(|actual| {
                actual.message_id != key.key.message_id
                    || actual.sent_at_ms != key.key.sent_at_ms
                    || actual.digest != key.key.digest
            })
        {
            return Err(PrivateGroupError::Codec(
                "frozen group history record changed".into(),
            ));
        }
        self.retained_history_record(&row, recipient, peer)
    }
}
