use super::*;
use crate::conversation::history::StoredMessage;
use crate::conversation::recovery::manifest::{digest, HistoryKey};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ChannelRecord {
    pub message_id: String,
    pub sent_at_ms: u64,
    pub from_device: String,
    pub from_fingerprint: String,
    pub content: Content,
    pub origin: Option<crate::message_deletion::MessageOrigin>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) enum Content {
    Text(String),
    Attachment(crate::conversation::previews::AttachmentOffer),
}

impl ChannelRecord {
    pub(super) fn from_stored(row: &StoredMessage<ChannelMessage>) -> Option<Self> {
        if row
            .message
            .metadata
            .as_ref()
            .is_some_and(|m| m.deletion.is_some())
        {
            return None;
        }
        Some(Self {
            message_id: row.message_id.clone(),
            sent_at_ms: row.sent_at_ms,
            from_device: row.message.from_device.clone(),
            from_fingerprint: row.message.from_fingerprint.clone(),
            content: if row.message.attachment.is_some() {
                Content::Attachment(crate::conversation::previews::AttachmentOffer {
                    manifest: row.attachment_manifest.clone()?,
                    preview_manifest: row.preview_manifest.clone(),
                })
            } else {
                Content::Text(row.message.body.clone())
            },
            origin: row.message.metadata.as_ref().and_then(|m| m.origin.clone()),
        })
    }

    pub(super) fn key(row: &StoredMessage<ChannelMessage>) -> Result<Option<HistoryKey>, String> {
        Self::from_stored(row)
            .map(|record| {
                Ok(HistoryKey {
                    message_id: record.message_id.clone(),
                    sent_at_ms: record.sent_at_ms,
                    digest: digest(&record)?,
                })
            })
            .transpose()
    }

    pub(super) fn occurrence(
        row: &StoredMessage<ChannelMessage>,
    ) -> Result<Option<crate::conversation::recovery::occurrence::Occurrence>, String> {
        let Some(record) = Self::from_stored(row) else {
            return Ok(None);
        };
        let identity = record
            .origin
            .as_ref()
            .map(|origin| origin.key())
            .transpose()?
            .unwrap_or(format!("legacy-{}", digest(&record)?));
        Ok(Some(
            crate::conversation::recovery::occurrence::Occurrence {
                native_id: record.message_id.clone(),
                row_key: format!(
                    "{}\u{1}{:020}\u{1}{}",
                    row.conversation_id, row.sent_at_ms, row.message_id
                ),
                identity,
                content_digest: digest(&record)?,
            },
        ))
    }

    pub(super) fn validate(&self, context: &str) -> Result<(), String> {
        if self.message_id.is_empty()
            || self.message_id.len() > 256
            || self.body().len() > MAX_BODY_LEN
            || self.from_device.len() > 1024
            || self.from_fingerprint.len() > 128
        {
            return Err("invalid channel history record".into());
        }
        if let Content::Attachment(offer) = &self.content {
            offer.verify(context, None)?;
            if offer.manifest.origin != self.origin
                || offer.manifest.from_fingerprint != self.from_fingerprint
            {
                return Err("history attachment origin differs".into());
            }
        }
        if let Some(origin) = &self.origin {
            match &self.content {
                Content::Text(body) => origin.verify(context, &self.message_id, body.as_bytes())?,
                Content::Attachment(offer) => {
                    if origin.id != self.message_id {
                        return Err("history attachment occurrence differs".into());
                    }
                    origin.verify_manifest(context, &offer.manifest)?;
                }
            }
            if origin.author != self.from_fingerprint.to_lowercase() {
                return Err("history original author differs".into());
            }
        }
        Ok(())
    }

    pub(super) fn body(&self) -> &str {
        match &self.content {
            Content::Text(body) => body,
            Content::Attachment(_) => "",
        }
    }

    pub(super) fn row(self, id: &str) -> StoredMessage<ChannelMessage> {
        let (body, attachment, attachment_manifest, preview_manifest) = match self.content {
            Content::Text(body) => (body, None, None, None),
            Content::Attachment(offer) => (
                String::new(),
                Some(crate::conversation::attachments::descriptor_of(
                    &offer.manifest,
                )),
                Some(offer.manifest),
                offer.preview_manifest,
            ),
        };
        StoredMessage {
            history_evidence: None,
            conversation_id: id.into(),
            sent_at_ms: self.sent_at_ms,
            message_id: self.message_id.clone(),
            message: ChannelMessage {
                metadata: self
                    .origin
                    .map(|origin| crate::message_deletion::MessageMetadata {
                        origin: Some(origin),
                        ..Default::default()
                    }),
                message_id: Some(self.message_id),
                sent_at_ms: Some(self.sent_at_ms),
                from_device: self.from_device,
                from_fingerprint: self.from_fingerprint,
                body,
                attachment,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
            },
            attachment_manifest,
            preview_manifest,
        }
    }
}
