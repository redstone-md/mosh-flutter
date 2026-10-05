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
#[path = "transfer_cleanup.rs"]
mod cleanup;
#[path = "preview_transfer.rs"]
mod previews;
#[path = "transfer_restore.rs"]
mod restore;

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
    pub(crate) preview: Option<Box<Outgoing>>,
}

/// Every attachment one conversation knows about: the transfers in flight, the
/// slots the UI reads, and the files on disk.
pub struct Transfer {
    runtime: AttachmentRuntime,
    slots: AttachmentSlots,
    store: Arc<AttachmentStore>,
    restored_outgoing: HashMap<String, AttachmentManifest>,
    leases: HashMap<String, (String, String)>,
    gc_after: Option<String>,
    previews: HashMap<String, AttachmentManifest>,
    pending_previews: std::collections::VecDeque<String>,
    preview_retry_after: HashMap<String, Instant>,
}

impl Transfer {
    pub(crate) fn forget(&mut self, id: &str) {
        self.forget_preview(id);
        self.runtime.forget(id);
        self.restored_outgoing.remove(id);
        self.slots.forget(id);
        self.release_lease(id);
    }
    pub fn new(store: Arc<AttachmentStore>) -> Self {
        Self {
            runtime: AttachmentRuntime::new(),
            slots: AttachmentSlots::default(),
            store,
            restored_outgoing: HashMap::new(),
            leases: HashMap::new(),
            gc_after: None,
            previews: HashMap::new(),
            pending_previews: Default::default(),
            preview_retry_after: Default::default(),
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
        let descriptor = descriptor_of(&manifest);
        let stored = self
            .with_lease(&descriptor, |transfer| {
                transfer
                    .store
                    .write_blob(&manifest.content_hash, &manifest.file_name, &bytes)
                    .map_err(Into::into)
            })
            .inspect_err(|_| self.runtime.forget(&manifest.attachment_id))?;
        Ok(Outgoing {
            descriptor,
            manifest,
            stored_path: stored.to_string_lossy().into_owned(),
            preview: None,
        })
    }

    /// Opens the slot for a manifest that is now on the wire, and hands back
    /// the descriptor to stamp on the message log.
    pub fn record_sent(&mut self, outgoing: Outgoing) -> AttachmentDescriptor {
        self.runtime.update_origin(&outgoing.manifest);
        if let Some(preview) = outgoing.preview {
            self.previews.insert(
                outgoing.manifest.attachment_id.clone(),
                preview.manifest.clone(),
            );
            self.record_sent(*preview);
        }
        self.slots
            .record_sent(outgoing.descriptor.clone(), outgoing.stored_path);
        outgoing.descriptor
    }

    /// A refused publication releases both prepared blobs' transfer leases.
    pub(crate) fn record_published<T, E>(
        &mut self,
        outgoing: Outgoing,
        publication: Result<T, E>,
    ) -> Result<(AttachmentDescriptor, T), E> {
        match publication {
            Ok(value) => Ok((self.record_sent(outgoing), value)),
            Err(error) => {
                if let Some(preview) = &outgoing.preview {
                    self.forget(&preview.manifest.attachment_id);
                }
                self.forget(&outgoing.manifest.attachment_id);
                Err(error)
            }
        }
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
        self.with_lease(&descriptor, |transfer| {
            transfer
                .runtime
                .register_incoming(manifest)
                .map_err(Into::into)
        })?;
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
                let path = match self.store.write_blob(&content_hash, &file_name, &bytes) {
                    Ok(path) => path,
                    Err(_) if self.is_preview(&attachment_id) => {
                        self.slots.fail(&attachment_id);
                        self.retry_preview(&attachment_id);
                        return Ok(());
                    }
                    Err(error) => return Err(error.into()),
                };
                self.slots
                    .complete_download(&attachment_id, path.to_string_lossy().into_owned());
            }
            Ok(_) => {}
            Err(_) => {
                self.slots.fail(&attachment_id);
                self.retry_preview(&attachment_id);
            }
        }
        Ok(())
    }

    /// Divide the shared peer queue between downloads so a large file cannot
    /// keep a voice note waiting for its first chunk.
    pub fn next_requests(&mut self) -> Vec<ChunkRequest> {
        self.next_requests_at(Instant::now())
    }

    pub(crate) fn next_requests_at(&mut self, now: Instant) -> Vec<ChunkRequest> {
        self.schedule_previews(now);
        let mut requests = Vec::new();
        let mut awaiting = self.slots.awaiting_chunks();
        awaiting.sort_by_key(|id| self.request_priority(id));
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

    /// What the UI shows for every attachment in this conversation.
    pub fn views(&self) -> Vec<AttachmentView> {
        self.slots
            .views(&self.runtime)
            .into_iter()
            .filter(|view| !self.is_preview(&view.attachment_id))
            .map(|mut view| {
                view.preview_path = self.preview_path(&view.attachment_id);
                view
            })
            .collect()
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
