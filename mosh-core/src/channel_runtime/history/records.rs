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
    #[serde(default)]
    pub legacy_id_absent: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) enum Content {
    Text(String),
    Attachment(Box<crate::conversation::previews::AttachmentOffer>),
    Erased {
        binding_digest: String,
        deletion_key: String,
    },
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
        let origin = row.message.metadata.as_ref().and_then(|m| m.origin.clone());
        let legacy_id_absent = origin.is_none()
            && (row.message.message_id.is_none()
                || is_legacy_id(&row.message_id)
                || row
                    .history_evidence
                    .as_ref()
                    .is_some_and(|e| e.legacy_original_id_absent));
        let mut record = Self {
            message_id: row.message_id.clone(),
            sent_at_ms: row.sent_at_ms,
            from_device: row.message.from_device.clone(),
            from_fingerprint: row.message.from_fingerprint.clone(),
            content: if row.message.attachment.is_some() {
                Content::Attachment(Box::new(crate::conversation::previews::AttachmentOffer {
                    manifest: row.attachment_manifest.clone()?,
                    preview_manifest: row.preview_manifest.clone(),
                }))
            } else {
                Content::Text(row.message.body.clone())
            },
            origin,
            legacy_id_absent,
        };
        if legacy_id_absent && !record.message_id.starts_with("legacy-") {
            record.message_id = format!(
                "legacy-{}",
                digest(&(
                    &row.conversation_id,
                    row.message.message_id.as_deref(),
                    row.sent_at_ms,
                    &record.from_device,
                    &record.from_fingerprint,
                    &record.content
                ))
                .ok()?
            );
        }
        Some(record)
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
        if let Some(metadata) = row
            .message
            .metadata
            .as_ref()
            .filter(|m| m.deletion.is_some())
        {
            if let Some(origin) = &metadata.origin {
                return Ok(Some(
                    crate::conversation::recovery::occurrence::Occurrence {
                        native_id: row.message_id.clone(),
                        row_key: format!(
                            "{}\u{1}{:020}\u{1}{}",
                            row.conversation_id, row.sent_at_ms, row.message_id
                        ),
                        identity: origin.key()?,
                        content_digest: None,
                    },
                ));
            }
            return Ok(None);
        }
        let Some(record) = Self::from_stored(row) else {
            return Ok(None);
        };
        let identity = record
            .origin
            .as_ref()
            .map(|origin| origin.key())
            .transpose()?
            .unwrap_or(format!("legacy-{}", record.semantic_digest()?));
        Ok(Some(
            crate::conversation::recovery::occurrence::Occurrence {
                native_id: record.message_id.clone(),
                row_key: format!(
                    "{}\u{1}{:020}\u{1}{}",
                    row.conversation_id, row.sent_at_ms, row.message_id
                ),
                identity,
                content_digest: Some(record.semantic_digest()?),
            },
        ))
    }

    pub(super) fn semantic_digest(&self) -> Result<String, String> {
        if self.origin.is_some() {
            return digest(&(
                &self.message_id,
                &self.from_fingerprint,
                &self.content,
                &self.origin,
            ));
        }
        digest(&(
            &self.message_id,
            (!self.legacy_id_absent).then_some(self.sent_at_ms),
            &self.from_device,
            &self.from_fingerprint,
            &self.content,
        ))
    }

    pub(super) fn validate(&self, context: &str) -> Result<(), String> {
        if (matches!(self.content, Content::Erased { .. }) && self.origin.is_none())
            || (self.legacy_id_absent && (self.origin.is_some() || !is_legacy_id(&self.message_id)))
            || self.message_id.is_empty()
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
                Content::Erased {
                    binding_digest,
                    deletion_key,
                } => {
                    origin.verify_signature()?;
                    if origin.conversation != context
                        || origin.id != self.message_id
                        || *deletion_key != origin.key()?
                        || binding_digest.len() != 64
                        || hex::decode(binding_digest).is_err()
                    {
                        return Err("invalid erased history target".into());
                    }
                }
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

    pub(super) fn binding_digest(&self) -> Result<String, String> {
        match &self.content {
            Content::Erased { binding_digest, .. } => Ok(binding_digest.clone()),
            _ => digest(self),
        }
    }

    pub(super) fn body(&self) -> &str {
        match &self.content {
            Content::Text(body) => body,
            Content::Attachment(_) | Content::Erased { .. } => "",
        }
    }

    pub(super) fn row(self, id: &str) -> StoredMessage<ChannelMessage> {
        let (body, attachment, attachment_manifest, preview_manifest) = match self.content {
            Content::Text(body) => (body, None, None, None),
            Content::Erased { .. } => (String::new(), None, None, None),
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

fn is_legacy_id(id: &str) -> bool {
    id.strip_prefix("legacy-")
        .is_some_and(|hash| hash.len() == 64 && hex::decode(hash).is_ok())
}

pub(super) fn legacy_id(name: &str, message: &ChannelMessage) -> Result<String, String> {
    Ok(format!(
        "legacy-{}",
        digest(&(
            name,
            Option::<String>::None,
            message.sent_at_ms,
            &message.from_device,
            &message.from_fingerprint,
            Content::Text(message.body.clone())
        ))?
    ))
}
