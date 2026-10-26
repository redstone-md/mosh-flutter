use super::*;
use crate::conversation::recovery::{cursor::PAGE_RECORDS, manifest::HistoryKey};

#[derive(Clone, Serialize, Deserialize)]
struct Export {
    round: u64,
    request_id: String,
    manifest: Manifest,
    deletion_digest: String,
}

impl ChannelSession {
    pub(super) fn history_manifest(&mut self) -> Result<Manifest, ChannelRuntimeError> {
        let count = self.messages.revision();
        if let Some((version, manifest)) = &self.recovery.cache {
            if *version == count {
                return Ok(manifest.clone());
            }
        }
        let store =
            self.deletions.store.as_ref().ok_or_else(|| {
                ChannelRuntimeError::Persistence("history store unavailable".into())
            })?;
        let manifest = store.recovery_manifest(CHANNEL_HISTORY, &self.name, ChannelRecord::key)?;
        self.recovery.cache = Some((count, manifest.clone()));
        Ok(manifest)
    }

    pub(super) fn serve_history(
        &mut self,
        frame: &HistoryFrame,
        manifest: String,
        offset: usize,
        fragment_offset: usize,
        deletion_digest: String,
        journal: bool,
        journal_after: Option<String>,
    ) -> Result<(), ChannelRuntimeError> {
        let current = self.history_manifest()?;
        let prefix = format!(
            "{}\u{1}export\u{1}{}",
            self.deletions.context, frame.sender_key
        );
        let store =
            self.deletions.store.as_ref().ok_or_else(|| {
                ChannelRuntimeError::Persistence("history store unavailable".into())
            })?;
        let mut export = store.recovery_state::<Export>(&format!("{prefix}\u{1}meta"))?;
        if export.as_ref().is_none_or(|e| e.round < frame.round)
            && offset == 0
            && current.digest == manifest
            && self.history_deletion_digest()? == deletion_digest
        {
            let next = Export {
                round: frame.round,
                request_id: frame.request_id.clone(),
                manifest: current,
                deletion_digest: deletion_digest.clone(),
            };
            let authority = self.deletion_authority()?;
            store.freeze_recovery(
                CHANNEL_HISTORY,
                &self.name,
                crate::persistence::FrozenExport {
                    prefix: &prefix,
                    meta_key: &format!("{prefix}\u{1}meta"),
                    header: &next,
                },
                ChannelRecord::key,
                self.deletions
                    .records
                    .values()
                    .filter(|r| {
                        r.scope == crate::message_deletion::DeleteScope::ForEveryone
                            && r.status != crate::message_deletion::DeletionStatus::Rejected
                            && authority.validate(r, &authority.local.key).is_ok()
                    })
                    .cloned(),
            )?;
            export = Some(next);
        }
        let Some(export) = export.filter(|e| {
            e.round == frame.round
                && e.request_id == frame.request_id
                && e.manifest.digest == manifest
                && e.deletion_digest == deletion_digest
                && offset <= e.manifest.total
        }) else {
            return self.reply_history(
                Some(frame.sender_key.clone()),
                frame.request_id.clone(),
                frame.round,
                HistoryMessage::Unavailable,
            );
        };
        if journal {
            let (records, next) = store.recovery_page(
                &format!("{prefix}\u{1}journal\u{1}"),
                journal_after.as_deref(),
            )?;
            return self.reply_history(
                Some(frame.sender_key.clone()),
                frame.request_id.clone(),
                frame.round,
                HistoryMessage::Journal {
                    manifest,
                    deletion_digest,
                    page: crate::message_deletion::protocol::DeletionMessage::State {
                        records,
                        next,
                    },
                },
            );
        }
        let mut records = Vec::new();
        let mut bytes = 0;
        let mut fragment = None;
        for index in offset
            ..export
                .manifest
                .total
                .min(offset.saturating_add(PAGE_RECORDS))
        {
            let key = store
                .recovery_state::<HistoryKey>(&format!("{prefix}\u{1}keys\u{1}{index:020}"))?
                .ok_or_else(|| ChannelRuntimeError::Codec("frozen history key missing".into()))?;
            let row = store
                .history_message::<ChannelMessage>(CHANNEL_HISTORY, &self.name, &key)?
                .ok_or_else(|| ChannelRuntimeError::Codec("history row unavailable".into()))?;
            let record = ChannelRecord::from_stored(&row)
                .ok_or_else(|| ChannelRuntimeError::Codec("history content unavailable".into()))?;
            if crate::conversation::recovery::manifest::digest(&record)
                .map_err(ChannelRuntimeError::Codec)?
                != key.digest
            {
                return Err(ChannelRuntimeError::Codec(
                    "frozen history record changed".into(),
                ));
            }
            let serialized = serde_json::to_vec(&record)
                .map_err(|e| ChannelRuntimeError::Codec(e.to_string()))?;
            if bytes + serialized.len() > 24_000 {
                if records.is_empty() {
                    fragment = Some(
                        crate::conversation::recovery::fragment::fragment(
                            &serialized,
                            fragment_offset,
                        )
                        .map_err(ChannelRuntimeError::Codec)?,
                    );
                }
                break;
            }
            if fragment_offset != 0 {
                return Err(ChannelRuntimeError::Codec(
                    "unexpected history fragment offset".into(),
                ));
            }
            bytes += serialized.len();
            records.push(record);
        }
        self.reply_history(
            Some(frame.sender_key.clone()),
            frame.request_id.clone(),
            frame.round,
            HistoryMessage::Page {
                manifest,
                total: export.manifest.total,
                offset,
                records,
                fragment,
            },
        )
    }
}
