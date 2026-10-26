//! Original authorship and immutable semantics remain separate from carrier signatures.
use super::{
    records::{is_legacy_id, Content},
    *,
};
use crate::conversation::recovery::manifest::digest;

impl ChannelRecord {
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
}
