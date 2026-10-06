//! Rebuild cached attachments and service existing playback ranges.

use super::*;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

impl Transfer {
    /// Serves a byte range for playback, pulling the attachment in whether or
    /// not the user ever pressed download.
    pub fn stream_range(&mut self, attachment_id: &str, start: u64, end: u64) -> StreamRange {
        self.slots
            .resume_for_stream(attachment_id, &mut self.runtime);
        let range = self.runtime.stream_range(attachment_id, start, end);
        if !matches!(range, StreamRange::Unknown) {
            return range;
        }
        let Some(descriptor) = self.slots.cached_descriptor(attachment_id) else {
            return StreamRange::Unknown;
        };
        let Ok(path) = self
            .store
            .path_for(&descriptor.content_hash, &descriptor.file_name)
        else {
            return StreamRange::Unknown;
        };
        let Ok(mut file) = File::open(path) else {
            return StreamRange::Unknown;
        };
        let Ok(metadata) = file.metadata() else {
            return StreamRange::Unknown;
        };
        if metadata.len() != descriptor.total_size {
            return StreamRange::Unknown;
        }
        let start = start.min(descriptor.total_size);
        let end = end.min(descriptor.total_size).max(start);
        let Ok(length) = usize::try_from(end - start) else {
            return StreamRange::Unknown;
        };
        let mut bytes = vec![0; length];
        if file.seek(SeekFrom::Start(start)).is_err() || file.read_exact(&mut bytes).is_err() {
            return StreamRange::Unknown;
        }
        StreamRange::Ready {
            bytes,
            total_size: descriptor.total_size,
            mime: descriptor.mime.clone(),
        }
    }

    /// Puts back an attachment whose bytes are still in the store. Used by
    /// older history rows that do not carry a chunk-crypto manifest.
    pub fn restore_cached(
        &mut self,
        descriptor: &AttachmentDescriptor,
        direction: AttachmentDirection,
    ) {
        let _ = self.retain_lease(descriptor);
        if !self.cached_valid(descriptor) {
            return;
        }
        let Ok(path) = self
            .store
            .path_for(&descriptor.content_hash, &descriptor.file_name)
        else {
            return;
        };
        self.slots.restore(
            descriptor.clone(),
            direction,
            path.to_string_lossy().into_owned(),
        );
    }

    /// Validate cached originals and previews without loading whole files into memory.
    pub(super) fn cached_valid(&self, descriptor: &AttachmentDescriptor) -> bool {
        let Ok(path) = self
            .store
            .path_for(&descriptor.content_hash, &descriptor.file_name)
        else {
            return false;
        };
        let Ok(mut file) = File::open(path) else {
            return false;
        };
        if !file
            .metadata()
            .is_ok_and(|metadata| metadata.len() == descriptor.total_size)
        {
            return false;
        }
        let mut hasher = crate::attachment_crypto::Sha256Builder::new();
        let mut buffer = [0; 32 * 1024];
        loop {
            match file.read(&mut buffer) {
                Ok(0) => return hasher.finish_hex() == descriptor.content_hash,
                Ok(length) => hasher.update(&buffer[..length]),
                Err(_) => return false,
            }
        }
    }

    /// Restores a saved offer or sender after restart. Older history rows have
    /// no manifest and can only restore files that are already cached.
    pub fn restore_stored(
        &mut self,
        descriptor: &AttachmentDescriptor,
        direction: AttachmentDirection,
        manifest: Option<AttachmentManifest>,
    ) {
        if self.holds(&descriptor.attachment_id) {
            return;
        }
        let manifest = manifest.filter(|value| {
            value.attachment_id == descriptor.attachment_id
                && value.content_hash == descriptor.content_hash
                && value.file_name == descriptor.file_name
                && value.mime == descriptor.mime
                && value.total_size == descriptor.total_size
        });
        self.restore_cached(descriptor, direction);
        if self.holds(&descriptor.attachment_id) {
            if direction == AttachmentDirection::Outgoing {
                if let Some(manifest) = manifest {
                    self.restored_outgoing
                        .insert(descriptor.attachment_id.clone(), manifest);
                }
            }
        } else if direction == AttachmentDirection::Incoming {
            if let Some(manifest) = manifest {
                let _ = self.accept_manifest(manifest);
            }
        }
    }
}
