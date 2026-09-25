//! The attachment slot table every conversation kind keeps.
//!
//! `AttachmentRuntime` owns the bytes: chunks, hashes, progress. This module
//! owns the bookkeeping around them — which attachment was offered, which one
//! the user asked for, where the finished file landed, what the UI should
//! show. The two must move together (asking for a download flips a slot flag
//! *and* starts the transfer), so the calls that pair them take the runtime as
//! an argument and do both.
//!
//! What stays with the kind: how a manifest, a chunk request and a chunk get
//! published. A channel sends them in the clear, a group wraps them in MLS, a
//! DM wraps them in MLS too and hands them to its transport.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::attachment_runtime::{AttachmentManifest, AttachmentRuntime, VoiceMeta, CHUNK_SIZE};

/// Immutable attachment metadata stamped onto the message log. Mutable
/// transfer state is reported separately through [`AttachmentView`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentDescriptor {
    pub attachment_id: String,
    pub content_hash: String,
    pub file_name: String,
    pub mime: String,
    pub total_size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thumbnail_b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice: Option<VoiceMeta>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AttachmentState {
    /// Bytes are on disk locally (sender's own file, or a finished download).
    Available,
    /// Manifest known, download not started yet.
    Offered,
    /// Chunks are in flight.
    Downloading,
    /// Transfer or verification failed; a retry is possible.
    Failed,
    /// Either side cancelled the transfer.
    Cancelled,
}

/// Live transfer state for one attachment, recomputed on every snapshot.
#[derive(Debug, Clone, Serialize)]
pub struct AttachmentView {
    pub attachment_id: String,
    pub direction: String,
    pub state: AttachmentState,
    pub completed_chunks: u64,
    pub chunk_count: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub local_path: Option<String>,
}

/// What a kind answers when the user sends a file. The conversation is named
/// the way its own kind names one: a DM session id, a group id, a channel name.
#[derive(Debug, Clone, Serialize)]
pub struct AttachmentSendResult {
    pub conversation_id: String,
    pub attachment_id: String,
    pub content_hash: String,
}

/// Shown for a chunk that arrives before its manifest, so the bytes still get
/// a name on disk.
const UNNAMED_FILE: &str = "file";
const OUTGOING_LABEL: &str = "outgoing";
const INCOMING_LABEL: &str = "incoming";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AttachmentDirection {
    Outgoing,
    Incoming,
}

/// What went wrong with a slot. Each runtime maps this onto its own error so
/// the messages the app sees do not change.
#[derive(Debug)]
pub enum SlotError {
    /// No slot with this id — the manifest never arrived, or the id is wrong.
    Missing(String),
    /// Only a received attachment can be downloaded; the local copy is already
    /// on disk.
    NotIncoming,
    /// The transfer layer refused the call.
    Transfer(String),
}

impl std::fmt::Display for SlotError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Missing(id) => write!(formatter, "attachment not found: {id}"),
            Self::NotIncoming => write!(formatter, "cannot download an outgoing attachment"),
            Self::Transfer(error) => write!(formatter, "{error}"),
        }
    }
}

impl std::error::Error for SlotError {}

struct AttachmentSlot {
    descriptor: AttachmentDescriptor,
    direction: AttachmentDirection,
    local_path: Option<String>,
    download_requested: bool,
    failed: bool,
    cancelled: bool,
}

impl AttachmentSlot {
    fn view(&self, attachments: &AttachmentRuntime) -> AttachmentView {
        let (direction, progress) = match self.direction {
            AttachmentDirection::Outgoing => (
                OUTGOING_LABEL,
                attachments.outgoing_progress(&self.descriptor.attachment_id),
            ),
            AttachmentDirection::Incoming => (
                INCOMING_LABEL,
                attachments.incoming_progress(&self.descriptor.attachment_id),
            ),
        };
        let completed_chunks = progress
            .as_ref()
            .map(|value| value.completed_chunks)
            .unwrap_or(0);
        // The manifest's own chunk size decides the count: a transfer from an
        // older sender still uses 32 KB chunks.
        let chunk_count = progress
            .as_ref()
            .map(|value| value.chunk_count)
            .unwrap_or_else(|| self.descriptor.total_size.div_ceil(u64::from(CHUNK_SIZE)))
            .max(1);
        let state = if self.cancelled {
            AttachmentState::Cancelled
        } else if self.failed {
            AttachmentState::Failed
        } else if self.local_path.is_some() {
            AttachmentState::Available
        } else if self.download_requested {
            AttachmentState::Downloading
        } else {
            AttachmentState::Offered
        };
        AttachmentView {
            attachment_id: self.descriptor.attachment_id.clone(),
            direction: direction.to_string(),
            state,
            completed_chunks,
            chunk_count,
            local_path: self.local_path.clone(),
        }
    }
}

/// Every attachment this conversation knows about, by attachment id.
#[derive(Default)]
pub struct AttachmentSlots {
    slots: HashMap<String, AttachmentSlot>,
}

impl AttachmentSlots {
    pub fn contains(&self, attachment_id: &str) -> bool {
        self.slots.contains_key(attachment_id)
    }

    /// Metadata for a file already saved on this device.
    pub fn cached_descriptor(&self, attachment_id: &str) -> Option<&AttachmentDescriptor> {
        self.slots
            .get(attachment_id)
            .filter(|slot| slot.local_path.is_some())
            .map(|slot| &slot.descriptor)
    }

    /// Records an attachment somebody else offered. The bytes are not here
    /// yet; the user has to ask for them.
    pub fn offer(&mut self, descriptor: AttachmentDescriptor) {
        self.insert(descriptor, AttachmentDirection::Incoming, None);
    }

    /// Records an attachment this device just sent. Its file is already on
    /// disk, so it is available at once.
    pub fn record_sent(&mut self, descriptor: AttachmentDescriptor, local_path: String) {
        self.insert(descriptor, AttachmentDirection::Outgoing, Some(local_path));
    }

    /// Puts back a slot whose file survived a restart. The first record wins:
    /// history is replayed oldest first, and the same attachment can be
    /// stamped on more than one message.
    pub fn restore(
        &mut self,
        descriptor: AttachmentDescriptor,
        direction: AttachmentDirection,
        local_path: String,
    ) {
        if self.contains(&descriptor.attachment_id) {
            return;
        }
        self.insert(descriptor, direction, Some(local_path));
    }

    /// The name to save incoming bytes under.
    pub fn file_name(&self, attachment_id: &str) -> String {
        self.slots
            .get(attachment_id)
            .map(|slot| slot.descriptor.file_name.clone())
            .unwrap_or_else(|| UNNAMED_FILE.to_string())
    }

    /// The download finished and the file is on disk.
    pub fn complete_download(&mut self, attachment_id: &str, local_path: String) {
        if let Some(slot) = self.slots.get_mut(attachment_id) {
            slot.local_path = Some(local_path);
            slot.failed = false;
        }
    }

    /// A chunk did not verify. The user can ask again.
    pub fn fail(&mut self, attachment_id: &str) {
        if let Some(slot) = self.slots.get_mut(attachment_id) {
            slot.failed = true;
        }
    }

    /// The user asked for this attachment. Flips the slot and starts the
    /// transfer, which is one act and must not half-happen.
    pub fn start_download(
        &mut self,
        attachment_id: &str,
        attachments: &mut AttachmentRuntime,
    ) -> Result<(), SlotError> {
        let slot = self
            .slots
            .get_mut(attachment_id)
            .ok_or_else(|| SlotError::Missing(attachment_id.to_string()))?;
        if slot.direction != AttachmentDirection::Incoming {
            return Err(SlotError::NotIncoming);
        }
        slot.download_requested = true;
        slot.failed = false;
        slot.cancelled = false;
        attachments
            .start_download(attachment_id)
            .map_err(|error| SlotError::Transfer(error.to_string()))
    }

    /// Playback wants bytes, so the transfer has to run whether or not the
    /// user pressed download. An id with no slot is ignored: the stream call
    /// answers with whatever the transfer layer has.
    pub fn resume_for_stream(&mut self, attachment_id: &str, attachments: &mut AttachmentRuntime) {
        if let Some(slot) = self.slots.get_mut(attachment_id) {
            slot.download_requested = true;
            slot.cancelled = false;
        }
        let _ = attachments.start_download(attachment_id);
    }

    pub fn cancel(
        &mut self,
        attachment_id: &str,
        attachments: &mut AttachmentRuntime,
    ) -> Result<(), SlotError> {
        let slot = self
            .slots
            .get_mut(attachment_id)
            .ok_or_else(|| SlotError::Missing(attachment_id.to_string()))?;
        slot.cancelled = true;
        slot.download_requested = false;
        attachments.cancel(attachment_id);
        Ok(())
    }

    /// The attachments that still need chunks pulled in, with voice first.
    pub fn awaiting_chunks(&self) -> Vec<String> {
        let mut ids: Vec<(bool, String)> = self
            .slots
            .iter()
            .filter(|(_, slot)| {
                slot.direction == AttachmentDirection::Incoming
                    && slot.download_requested
                    && slot.local_path.is_none()
                    && !slot.cancelled
            })
            .map(|(id, slot)| (slot.descriptor.voice.is_none(), id.clone()))
            .collect();
        ids.sort();
        ids.into_iter().map(|(_, id)| id).collect()
    }

    /// What the UI shows, sorted so the list does not jump between polls.
    pub fn views(&self, attachments: &AttachmentRuntime) -> Vec<AttachmentView> {
        let mut views: Vec<AttachmentView> = self
            .slots
            .values()
            .map(|slot| slot.view(attachments))
            .collect();
        views.sort_by(|a, b| a.attachment_id.cmp(&b.attachment_id));
        views
    }

    fn insert(
        &mut self,
        descriptor: AttachmentDescriptor,
        direction: AttachmentDirection,
        local_path: Option<String>,
    ) {
        self.slots.insert(
            descriptor.attachment_id.clone(),
            AttachmentSlot {
                descriptor,
                direction,
                local_path,
                download_requested: false,
                failed: false,
                cancelled: false,
            },
        );
    }
}

/// The immutable half of a manifest, the part that is stamped onto the message
/// log and never changes again.
pub fn descriptor_of(manifest: &AttachmentManifest) -> AttachmentDescriptor {
    AttachmentDescriptor {
        attachment_id: manifest.attachment_id.clone(),
        content_hash: manifest.content_hash.clone(),
        file_name: manifest.file_name.clone(),
        mime: manifest.mime.clone(),
        total_size: manifest.total_size,
        thumbnail_b64: manifest.thumbnail_b64.clone(),
        voice: manifest.voice.clone(),
    }
}

#[cfg(test)]
#[path = "attachments_tests.rs"]
mod tests;
