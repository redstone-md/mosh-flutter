//! A frozen cursor slot survives deletion without retaining old fragment bytes.
use super::*;
use crate::conversation::history::StoredMessage;

impl ChannelSession {
    pub(super) fn erased_history_record(
        &self,
        row: &StoredMessage<ChannelMessage>,
        digest: &str,
    ) -> Result<ChannelRecord, ChannelRuntimeError> {
        let origin = row
            .message
            .metadata
            .as_ref()
            .and_then(|m| m.origin.clone())
            .ok_or_else(|| {
                ChannelRuntimeError::Codec("erased history origin unavailable".into())
            })?;
        let authority = self.deletion_authority()?;
        let deletion = self
            .deletions
            .records
            .values()
            .find(|r| {
                r.scope == crate::message_deletion::DeleteScope::ForEveryone
                    && r.request.as_ref().is_some_and(|q| q.target == origin)
                    && authority.validate(r, &authority.local.key).is_ok()
            })
            .ok_or_else(|| {
                ChannelRuntimeError::Codec("erased history evidence unavailable".into())
            })?;
        self.publish_deletion(&crate::message_deletion::protocol::DeletionMessage::State {
            records: vec![deletion.clone()],
            next: None,
        })?;
        Ok(ChannelRecord {
            message_id: origin.id.clone(),
            sent_at_ms: row.sent_at_ms,
            from_device: row.message.from_device.clone(),
            from_fingerprint: row.message.from_fingerprint.clone(),
            content: records::Content::Erased {
                binding_digest: digest.into(),
                deletion_key: deletion.key.clone(),
            },
            origin: Some(origin),
            legacy_id_absent: false,
        })
    }
}
