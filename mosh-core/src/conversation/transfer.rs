//! An attachment's bytes, on their way out and on their way in.
//!
//! Three things had to move together and were written out three times: the
//! transfer layer that seals and verifies chunks, the slot table that says
//! what the UI should show, and the store that keeps the finished file. They
//! are one thing here. Sending a file seals it, saves this device's copy and
//! opens a slot; taking a manifest in opens a slot the other way round;
//! chunks are served from one side and filed on the other.
//!
//! What stays with the kind: publishing. A channel puts a manifest, a chunk
//! request and a chunk on the wire in the clear, a group wraps them in MLS, a
//! DM wraps them in MLS too and hands them to its transport. So the calls
//! here hand back the frames to publish instead of publishing them.

use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::sync::Arc;
use std::time::Instant;

use super::attachments::{
    descriptor_of, AttachmentDescriptor, AttachmentDirection, AttachmentSlots, AttachmentView,
    SlotError,
};
use crate::attachment_runtime::{
    AttachmentManifest, AttachmentRuntime, ChunkFrame, ChunkOutcome, ChunkRequest,
    OutgoingAttachment, StreamRange,
};
use crate::attachment_store::AttachmentStore;
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};

/// What went wrong moving an attachment's bytes. Each runtime maps this onto
/// its own error, so the messages the app shows do not change.
#[derive(Debug)]
pub enum TransferError {
    /// Sealing, verifying or storing the bytes refused the call.
    Bytes(String),
    /// The slot table refused it: no such attachment, or the wrong direction.
    Slot(SlotError),
}

impl std::fmt::Display for TransferError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Bytes(error) => write!(formatter, "{error}"),
            Self::Slot(error) => write!(formatter, "{error}"),
        }
    }
}

impl std::error::Error for TransferError {}

impl From<crate::attachment_runtime::AttachmentRuntimeError> for TransferError {
    fn from(error: crate::attachment_runtime::AttachmentRuntimeError) -> Self {
        Self::Bytes(error.to_string())
    }
}

impl From<crate::attachment_store::AttachmentStoreError> for TransferError {
    fn from(error: crate::attachment_store::AttachmentStoreError) -> Self {
        Self::Bytes(error.to_string())
    }
}

impl From<SlotError> for TransferError {
    fn from(error: SlotError) -> Self {
        Self::Slot(error)
    }
}

/// A file sealed and saved, waiting for its kind to put the manifest on the
/// wire. Held between [`Transfer::prepare_outgoing`] and
/// [`Transfer::record_sent`] so the two steps cannot be mixed up.
pub struct Outgoing {
    /// What the kind publishes.
    pub manifest: AttachmentManifest,
    /// What the kind stamps on the message log, once the manifest is out.
    pub descriptor: AttachmentDescriptor,
    stored_path: String,
}

/// Every attachment one conversation knows about: the transfers in flight, the
/// slots the UI reads, and the files on disk.
pub struct Transfer {
    runtime: AttachmentRuntime,
    slots: AttachmentSlots,
    store: Arc<AttachmentStore>,
    restored_outgoing: HashMap<String, AttachmentManifest>,
}

impl Transfer {
    pub fn new(store: Arc<AttachmentStore>) -> Self {
        Self {
            runtime: AttachmentRuntime::new(),
            slots: AttachmentSlots::default(),
            store,
            restored_outgoing: HashMap::new(),
        }
    }

    /// True when this conversation already knows the attachment.
    pub fn holds(&self, attachment_id: &str) -> bool {
        self.slots.contains(attachment_id)
    }

    /// Seals a file for sending and keeps this device's own copy on disk.
    ///
    /// The slot stays shut until [`record_sent`](Self::record_sent). The kind
    /// publishes the manifest in between, and a publish that fails must not
    /// leave an attachment the UI can show with no message beside it.
    pub fn prepare_outgoing(
        &mut self,
        outgoing: OutgoingAttachment,
    ) -> Result<Outgoing, TransferError> {
        let bytes = outgoing.bytes.clone();
        let manifest = self.runtime.prepare_outgoing(outgoing)?;
        let stored = self
            .store
            .write_blob(&manifest.content_hash, &manifest.file_name, &bytes)?;
        Ok(Outgoing {
            descriptor: descriptor_of(&manifest),
            manifest,
            stored_path: stored.to_string_lossy().into_owned(),
        })
    }

    /// Opens the slot for a manifest that is now on the wire, and hands back
    /// the descriptor to stamp on the message log.
    pub fn record_sent(&mut self, outgoing: Outgoing) -> AttachmentDescriptor {
        self.slots
            .record_sent(outgoing.descriptor.clone(), outgoing.stored_path);
        outgoing.descriptor
    }

    /// Takes in a manifest somebody else published. `None` when the
    /// attachment is already known, so a repeat offer does not stamp a second
    /// message on the log.
    pub fn accept_manifest(
        &mut self,
        manifest: AttachmentManifest,
    ) -> Result<Option<AttachmentDescriptor>, TransferError> {
        if self.holds(&manifest.attachment_id) {
            return Ok(None);
        }
        let descriptor = descriptor_of(&manifest);
        self.runtime.register_incoming(manifest)?;
        self.slots.offer(descriptor.clone());
        Ok(Some(descriptor))
    }

    /// The chunks to answer a peer's request with. Only the sender holds the
    /// outgoing transfer, so every other member answers with nothing.
    pub fn serve(&mut self, request: &ChunkRequest) -> Vec<ChunkFrame> {
        if let Some(manifest) = self.restored_outgoing.get(&request.attachment_id).cloned() {
            let restored = self
                .store
                .read_blob(&manifest.content_hash, &manifest.file_name)
                .map_err(TransferError::from)
                .and_then(|bytes| {
                    self.runtime
                        .restore_outgoing(manifest, bytes)
                        .map_err(Into::into)
                });
            if let Err(error) = restored {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &request.attachment_id,
                    &format!("cannot restore sent attachment: {error}"),
                );
                return Vec::new();
            }
            self.restored_outgoing.remove(&request.attachment_id);
        }
        self.runtime.serve_chunks(request).unwrap_or_default()
    }

    /// The crypto manifest saved with a message's encrypted history row.
    pub fn manifest_for(&self, attachment_id: &str) -> Option<AttachmentManifest> {
        self.restored_outgoing
            .get(attachment_id)
            .cloned()
            .or_else(|| self.runtime.manifest_of(attachment_id))
    }

    /// Files one arriving chunk, and writes the file out once the last one
    /// lands. A chunk that does not verify fails the slot instead of the call:
    /// the user can ask for the attachment again.
    pub fn ingest(&mut self, frame: &ChunkFrame) -> Result<(), TransferError> {
        let attachment_id = frame.attachment_id.clone();
        let file_name = self.slots.file_name(&attachment_id);
        match self.runtime.ingest_chunk(frame) {
            Ok(ChunkOutcome::Complete {
                content_hash,
                bytes,
                ..
            }) => {
                let path = self.store.write_blob(&content_hash, &file_name, &bytes)?;
                self.slots
                    .complete_download(&attachment_id, path.to_string_lossy().into_owned());
            }
            Ok(_) => {}
            Err(_) => self.slots.fail(&attachment_id),
        }
        Ok(())
    }

    /// Divide the shared peer queue between downloads so a large file cannot
    /// keep a voice note waiting for its first chunk.
    pub fn next_requests(&mut self) -> Vec<ChunkRequest> {
        let mut requests = Vec::new();
        let awaiting = self.slots.awaiting_chunks();
        let now = Instant::now();
        for (position, attachment_id) in awaiting.iter().enumerate() {
            let remaining = awaiting.len() - position;
            let available = self.runtime.available_request_slots_at(now);
            let budget = available.div_ceil(remaining);
            if let Some(request) =
                self.runtime
                    .next_chunk_request_with_budget_at(attachment_id, now, budget)
            {
                requests.push(request);
            }
        }
        requests
    }

    /// The user asked for an attachment somebody else offered.
    pub fn start_download(&mut self, attachment_id: &str) -> Result<(), TransferError> {
        Ok(self
            .slots
            .start_download(attachment_id, &mut self.runtime)?)
    }

    pub fn cancel(&mut self, attachment_id: &str) -> Result<(), TransferError> {
        Ok(self.slots.cancel(attachment_id, &mut self.runtime)?)
    }

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
        if !self
            .store
            .exists(&descriptor.content_hash, &descriptor.file_name)
            .unwrap_or(false)
        {
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

    /// What the UI shows for every attachment in this conversation.
    pub fn views(&self) -> Vec<AttachmentView> {
        self.slots.views(&self.runtime)
    }

    /// How many times this device has handed out one chunk. The receiver only
    /// asks again for what it never got, so a second serve is the recovery
    /// from a lost chunk working.
    pub fn served_count(&self, attachment_id: &str, chunk_index: u64) -> u32 {
        self.runtime.served_count(attachment_id, chunk_index)
    }
}

#[cfg(test)]
#[path = "transfer_tests.rs"]
mod tests;
