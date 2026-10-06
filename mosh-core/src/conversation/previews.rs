//! A compatible main manifest and its independently authenticated preview.

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::attachment_runtime::{AttachmentManifest, VoiceMeta, CHUNK_SIZE};
use crate::mls_crypto::MlsSessionCrypto;
use crate::persistence::Persistence;

use super::transfer::{Outgoing, TransferError};

pub const MAX_MINIATURE_BASE64: usize = 2048;
pub const MAX_PREVIEW_BYTES: u64 = 128 * 1024;
pub(crate) const PREVIEW_FILE_NAME: &str = "preview.jpg";

/// Native input keeps the optional clear preview beside the original bytes.
pub struct AttachmentInput {
    pub file_name: String,
    pub mime: String,
    pub bytes: Vec<u8>,
    pub thumbnail: Option<String>,
    pub preview: Option<Vec<u8>>,
    pub voice: Option<VoiceMeta>,
}

/// Legacy readers decode the flattened main fields and ignore the extension.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentOffer {
    #[serde(flatten)]
    pub manifest: AttachmentManifest,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview_manifest: Option<AttachmentManifest>,
}

pub(crate) fn preview_id(parent: &str) -> String {
    format!("{parent}/preview")
}

fn preview_context(context: &str, parent: &str) -> String {
    format!("{context}/preview/{parent}")
}

impl AttachmentOffer {
    pub(crate) fn validate_preview(&self) -> Result<(), String> {
        let Some(preview) = &self.preview_manifest else {
            return Ok(());
        };
        let miniature = self.manifest.thumbnail_b64.as_deref().unwrap_or_default();
        let jpeg =
            crate::conversation::decode(miniature).map_err(|_| "invalid miniature base64")?;
        if !(self.manifest.mime.starts_with("image/") || self.manifest.mime.starts_with("video/"))
            || miniature.is_empty()
            || miniature.len() > MAX_MINIATURE_BASE64
            || !jpeg.starts_with(&[0xff, 0xd8, 0xff])
            || preview.attachment_id != preview_id(&self.manifest.attachment_id)
            || preview.file_name != PREVIEW_FILE_NAME
            || preview.mime != "image/jpeg"
            || preview.total_size == 0
            || preview.total_size > MAX_PREVIEW_BYTES
            || preview.chunk_size != CHUNK_SIZE
            || preview.chunk_count != preview.total_size.div_ceil(u64::from(CHUNK_SIZE))
            || preview.from_fingerprint != self.manifest.from_fingerprint
            || preview.thumbnail_b64.is_some()
            || preview.voice.is_some()
        {
            return Err("invalid attachment preview descriptor".into());
        }
        Ok(())
    }

    pub(crate) fn verify(&self, context: &str, signer: Option<&[u8]>) -> Result<(), String> {
        self.validate_preview()?;
        if let Some(origin) = &self.manifest.origin {
            if let Some(signer) = signer {
                origin.verify_manifest_from_signer(context, &self.manifest, signer)?;
            } else {
                origin.verify_manifest(context, &self.manifest)?;
            }
        }
        if let Some(preview) = &self.preview_manifest {
            let parent = self
                .manifest
                .origin
                .as_ref()
                .ok_or("unsigned preview parent")?;
            let origin = preview
                .origin
                .as_ref()
                .ok_or("unsigned attachment preview")?;
            origin.verify_manifest(&preview_context(context, &parent.id), preview)?;
            if origin.author != parent.author {
                return Err("attachment preview signer mismatch".into());
            }
        }
        Ok(())
    }
}

impl Outgoing {
    pub fn offer(&self) -> AttachmentOffer {
        AttachmentOffer {
            manifest: self.manifest.clone(),
            preview_manifest: self
                .preview
                .as_ref()
                .map(|preview| preview.manifest.clone()),
        }
    }

    pub(crate) fn sign_mls(
        &mut self,
        context: &str,
        crypto: &MlsSessionCrypto,
        store: Option<&Arc<Persistence>>,
        peer: Option<&str>,
    ) -> Result<crate::message_deletion::MessageOrigin, String> {
        let origin = crate::message_deletion::MessageOrigin::sign_mls(
            context,
            &self.manifest.attachment_id,
            &crate::message_deletion::MessageOrigin::manifest_bytes(&self.manifest)?,
            crypto,
            store,
            peer,
        )?;
        self.manifest.origin = Some(origin.clone());
        if let Some(preview) = &mut self.preview {
            // Account ownership belongs to the parent; the child binds its signer.
            preview.sign_mls(
                &preview_context(context, &self.manifest.attachment_id),
                crypto,
                None,
                None,
            )?;
        }
        Ok(origin)
    }

    pub(crate) fn sign(
        &mut self,
        context: &str,
        key: &ed25519_dalek::SigningKey,
        store: Option<&Arc<Persistence>>,
    ) -> Result<crate::message_deletion::MessageOrigin, String> {
        let origin = crate::message_deletion::MessageOrigin::sign(
            context,
            &self.manifest.attachment_id,
            &crate::message_deletion::MessageOrigin::manifest_bytes(&self.manifest)?,
            key,
            store,
        )?;
        self.manifest.origin = Some(origin.clone());
        if let Some(preview) = &mut self.preview {
            preview.sign(
                &preview_context(context, &self.manifest.attachment_id),
                key,
                None,
            )?;
        }
        Ok(origin)
    }
}

pub(crate) fn validate_preview_bytes(bytes: &[u8]) -> Result<(), TransferError> {
    if bytes.len() as u64 > MAX_PREVIEW_BYTES || !bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        return Err(TransferError::Bytes(
            "invalid or oversized JPEG preview".into(),
        ));
    }
    Ok(())
}

impl From<AttachmentManifest> for AttachmentOffer {
    fn from(manifest: AttachmentManifest) -> Self {
        Self {
            manifest,
            preview_manifest: None,
        }
    }
}
