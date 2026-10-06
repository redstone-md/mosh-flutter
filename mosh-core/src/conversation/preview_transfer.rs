//! Auxiliary blobs share chunk crypto, cache leases and the request scheduler.

use super::*;
use crate::conversation::previews::{
    preview_id, validate_preview_bytes, AttachmentOffer, PREVIEW_FILE_NAME,
};

#[path = "preview_scheduler.rs"]
mod scheduler;

impl Transfer {
    pub fn prepare_offer(
        &mut self,
        outgoing: OutgoingAttachment,
        preview: Option<Vec<u8>>,
    ) -> Result<Outgoing, TransferError> {
        if let Some(bytes) = &preview {
            validate_preview_bytes(bytes)?;
        }
        let mut prepared = self.prepare_outgoing(outgoing)?;
        if let Some(bytes) = preview {
            let result = self.prepare_outgoing(OutgoingAttachment {
                attachment_id: preview_id(&prepared.manifest.attachment_id),
                file_name: PREVIEW_FILE_NAME.into(),
                mime: "image/jpeg".into(),
                from_fingerprint: prepared.manifest.from_fingerprint.clone(),
                bytes,
                thumbnail_b64: None,
                voice: None,
            });
            match result {
                Ok(preview) => prepared.preview = Some(Box::new(preview)),
                Err(error) => {
                    self.forget(&prepared.manifest.attachment_id);
                    return Err(error);
                }
            }
        }
        if let Err(error) = prepared.offer().validate_preview() {
            self.forget(&prepared.manifest.attachment_id);
            if let Some(preview) = &prepared.preview {
                self.forget(&preview.manifest.attachment_id);
            }
            return Err(TransferError::Bytes(error));
        }
        Ok(prepared)
    }

    pub fn accept_offer(
        &mut self,
        offer: AttachmentOffer,
    ) -> Result<Option<AttachmentDescriptor>, TransferError> {
        offer.validate_preview().map_err(TransferError::Bytes)?;
        let parent = offer.manifest.attachment_id.clone();
        let Some(descriptor) = self.accept_manifest(offer.manifest)? else {
            return Ok(None);
        };
        if let Some(preview) = offer.preview_manifest {
            if let Err(error) =
                self.install_preview(&parent, preview, AttachmentDirection::Incoming)
            {
                self.forget(&parent);
                return Err(error);
            }
        }
        Ok(Some(descriptor))
    }

    fn install_preview(
        &mut self,
        parent: &str,
        manifest: AttachmentManifest,
        direction: AttachmentDirection,
    ) -> Result<(), TransferError> {
        if self.previews.contains_key(parent) {
            return Ok(());
        }
        let descriptor = descriptor_of(&manifest);
        let cached = self.cached_valid(&descriptor);
        if cached {
            self.restore_stored(&descriptor, direction, Some(manifest.clone()));
        } else if direction == AttachmentDirection::Incoming {
            self.accept_manifest(manifest.clone())?;
        } else {
            return Ok(());
        }
        if !cached {
            self.pending_previews
                .push_front(manifest.attachment_id.clone());
        }
        self.previews.insert(parent.into(), manifest);
        Ok(())
    }

    pub(crate) fn restore_preview(
        &mut self,
        offer: AttachmentOffer,
        direction: AttachmentDirection,
    ) {
        let Some(origin) = &offer.manifest.origin else {
            return;
        };
        if offer.verify(&origin.conversation, None).is_err() {
            return;
        }
        if let Some(preview) = offer.preview_manifest {
            let parent = &offer.manifest.attachment_id;
            if self.install_preview(parent, preview, direction).is_ok()
                && self.previews.contains_key(parent)
                && !self.holds(parent)
            {
                self.slots
                    .restore_metadata(descriptor_of(&offer.manifest), direction);
            }
        }
    }

    pub fn preview_path(&self, parent: &str) -> Option<String> {
        let manifest = self.previews.get(parent)?;
        let descriptor = self.slots.cached_descriptor(&manifest.attachment_id)?;
        self.store
            .path_for(&descriptor.content_hash, &descriptor.file_name)
            .ok()
            .filter(|path| path.is_file())
            .map(|path| path.to_string_lossy().into_owned())
    }

    pub(crate) fn preview_manifest_for(&self, parent: &str) -> Option<AttachmentManifest> {
        self.previews.get(parent).cloned()
    }

    pub(crate) fn erasure_descriptors(
        &self,
        attachment: &AttachmentDescriptor,
    ) -> Vec<AttachmentDescriptor> {
        let mut descriptors = vec![attachment.clone()];
        if let Some(preview) = self.previews.get(&attachment.attachment_id) {
            descriptors.push(descriptor_of(preview));
        }
        descriptors
    }

    pub(crate) fn visible_attachment_id<'a>(&self, id: &'a str) -> &'a str {
        id.strip_suffix("/preview")
            .filter(|parent| self.previews.contains_key(*parent))
            .unwrap_or(id)
    }

    pub(super) fn is_preview(&self, id: &str) -> bool {
        id.strip_suffix("/preview")
            .is_some_and(|parent| self.previews.contains_key(parent))
    }

    pub(super) fn forget_preview(&mut self, parent: &str) {
        if let Some(preview) = self.previews.remove(parent) {
            self.pending_previews
                .retain(|id| id != &preview.attachment_id);
            self.preview_retry_after.remove(&preview.attachment_id);
            self.forget(&preview.attachment_id);
        }
    }
}
