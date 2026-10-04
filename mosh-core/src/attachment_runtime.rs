//! Attachment transfer owner. Serving, admission, scheduling, and playback are feature-local modules.
use crate::attachment_crypto::{
    decrypt_chunk, encrypt_chunk, random_key, random_nonce_prefix, sha256_hex,
    AttachmentCryptoError, ATTACHMENT_KEY_LEN, ATTACHMENT_NONCE_PREFIX_LEN,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::time::{Duration, Instant};

mod incoming;
mod outgoing;
mod requests;
mod stream_range;
#[cfg(test)]
mod tests;

// Chunk envelopes fit macOS's default 9216-byte UDP datagram limit.
pub const CHUNK_SIZE: u32 = 4 * 1024;
pub const MAX_ATTACHMENT_SIZE: u64 = 50 * 1024 * 1024;
// Inline thumbnails must leave room for the encrypted gossipsub envelope.
const MAX_THUMBNAIL_B64: usize = 32 * 1024;
const REQUEST_WINDOW_BYTES: u64 = 2 * 1024 * 1024;
// Moss's queue holds 256 frames per peer, across all active downloads.
const MAX_REQUEST_BATCH: usize = 256;
const CHUNK_REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
fn request_batch(chunk_size: u32) -> usize {
    let per_window = REQUEST_WINDOW_BYTES / u64::from(chunk_size.max(1));
    (per_window as usize).clamp(1, MAX_REQUEST_BATCH)
}

#[derive(Debug)]
pub enum AttachmentRuntimeError {
    TooLarge { size: u64 },
    Empty,
    Crypto(String),
    UnknownTransfer(String),
    DuplicateTransfer(String),
    ManifestMismatch(String),
    Codec(String),
}

impl std::fmt::Display for AttachmentRuntimeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooLarge { size } => write!(
                formatter,
                "attachment of {size} bytes exceeds the {MAX_ATTACHMENT_SIZE}-byte limit"
            ),
            Self::Empty => write!(formatter, "attachment is empty"),
            Self::Crypto(error) => write!(formatter, "attachment crypto: {error}"),
            Self::UnknownTransfer(id) => write!(formatter, "unknown attachment transfer: {id}"),
            Self::DuplicateTransfer(id) => {
                write!(formatter, "attachment transfer already registered: {id}")
            }
            Self::ManifestMismatch(detail) => {
                write!(formatter, "attachment manifest invalid: {detail}")
            }
            Self::Codec(error) => write!(formatter, "attachment codec: {error}"),
        }
    }
}

impl std::error::Error for AttachmentRuntimeError {}

impl From<AttachmentCryptoError> for AttachmentRuntimeError {
    fn from(error: AttachmentCryptoError) -> Self {
        Self::Crypto(error.to_string())
    }
}

/// Marks a recorded voice message, with duration and waveform.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoiceMeta {
    /// Recording length in milliseconds.
    pub duration_ms: u32,
    /// 64 amplitude buckets (one byte each, 0-255), base64-encoded.
    pub peaks_b64: String,
}

/// Secret material and metadata sent through the conversation control path.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentManifest {
    pub attachment_id: String,
    pub content_hash: String,
    pub file_name: String,
    pub mime: String,
    pub total_size: u64,
    pub chunk_size: u32,
    pub chunk_count: u64,
    pub key_b64: String,
    pub nonce_prefix_b64: String,
    pub thumbnail_b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice: Option<VoiceMeta>,
    pub from_fingerprint: String,
}

/// Inputs for registering an outgoing transfer. Grouped into one value so call
/// sites name each field rather than threading a long positional list.
pub struct OutgoingAttachment {
    pub attachment_id: String,
    pub file_name: String,
    pub mime: String,
    pub from_fingerprint: String,
    pub bytes: Vec<u8>,
    pub thumbnail_b64: Option<String>,
    pub voice: Option<VoiceMeta>,
}

/// Receiver -> sender: asks for a batch of chunk indices. Plain metadata, so
/// it can ride the dedicated blob channel without extra protection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChunkRequest {
    pub attachment_id: String,
    pub chunk_indices: Vec<u64>,
}

/// Sender -> receiver: one AES-GCM encrypted chunk on the blob channel.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChunkFrame {
    pub attachment_id: String,
    pub chunk_index: u64,
    pub ciphertext_b64: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferState {
    Active,
    Complete,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
pub struct TransferProgress {
    pub attachment_id: String,
    pub file_name: String,
    pub total_size: u64,
    pub chunk_count: u64,
    pub completed_chunks: u64,
    pub state: TransferState,
}

#[derive(Debug)]
pub enum ChunkOutcome {
    Progress(TransferProgress),
    Complete {
        attachment_id: String,
        content_hash: String,
        bytes: Vec<u8>,
    },
    Duplicate,
    Unknown,
}

/// Result of asking an incoming transfer for a byte range.
#[derive(Debug)]
pub enum StreamRange {
    /// Every covering chunk is present; the decrypted slice is returned.
    Ready {
        bytes: Vec<u8>,
        total_size: u64,
        mime: String,
    },
    /// Some covering chunk is still missing; the download was nudged
    /// toward it.
    Pending {
        total_size: u64,
    },
    Unknown,
}

struct OutgoingTransfer {
    manifest: AttachmentManifest,
    plaintext: Vec<u8>,
    key: [u8; ATTACHMENT_KEY_LEN],
    nonce_prefix: [u8; ATTACHMENT_NONCE_PREFIX_LEN],
    /// Re-serving the same chunk is the transfer recovery mechanism.
    served_chunks: BTreeMap<u64, u32>,
    state: TransferState,
}

struct IncomingTransfer {
    manifest: AttachmentManifest,
    key: [u8; ATTACHMENT_KEY_LEN],
    nonce_prefix: [u8; ATTACHMENT_NONCE_PREFIX_LEN],
    chunks: BTreeMap<u64, Vec<u8>>,
    state: TransferState,
    download_started: bool,
    request_cursor: u64,
    /// Recent requests remain in flight until their timeout.
    requested_at: HashMap<u64, Instant>,
    /// When a streaming player asks for bytes the receiver does not have
    /// yet, this chunk index is fetched ahead of the sequential cursor.
    priority_chunk: Option<u64>,
}

pub struct AttachmentRuntime {
    outgoing: HashMap<String, OutgoingTransfer>,
    incoming: HashMap<String, IncomingTransfer>,
}

impl AttachmentRuntime {
    pub fn new() -> Self {
        Self {
            outgoing: HashMap::new(),
            incoming: HashMap::new(),
        }
    }

    pub fn manifest_of(&self, attachment_id: &str) -> Option<AttachmentManifest> {
        self.outgoing
            .get(attachment_id)
            .map(|transfer| &transfer.manifest)
            .or_else(|| {
                self.incoming
                    .get(attachment_id)
                    .map(|transfer| &transfer.manifest)
            })
            .cloned()
    }

    pub fn served_count(&self, attachment_id: &str, chunk_index: u64) -> u32 {
        self.outgoing
            .get(attachment_id)
            .and_then(|transfer| transfer.served_chunks.get(&chunk_index).copied())
            .unwrap_or(0)
    }

    pub fn cancel(&mut self, attachment_id: &str) {
        let outgoing = self
            .outgoing
            .get_mut(attachment_id)
            .map(|transfer| &mut transfer.state);
        let incoming = self
            .incoming
            .get_mut(attachment_id)
            .map(|transfer| &mut transfer.state);
        for state in outgoing.into_iter().chain(incoming) {
            if *state == TransferState::Active {
                *state = TransferState::Cancelled;
            }
        }
    }

    pub fn forget(&mut self, attachment_id: &str) {
        self.outgoing.remove(attachment_id);
        self.incoming.remove(attachment_id);
    }

    pub fn outgoing_progress(&self, attachment_id: &str) -> Option<TransferProgress> {
        self.outgoing.get(attachment_id).map(|transfer| {
            progress_of(
                &transfer.manifest,
                transfer.served_chunks.len() as u64,
                transfer.state,
            )
        })
    }

    pub fn incoming_progress(&self, attachment_id: &str) -> Option<TransferProgress> {
        self.incoming.get(attachment_id).map(|transfer| {
            progress_of(
                &transfer.manifest,
                transfer.chunks.len() as u64,
                transfer.state,
            )
        })
    }
}

impl Default for AttachmentRuntime {
    fn default() -> Self {
        Self::new()
    }
}

fn progress_of(
    manifest: &AttachmentManifest,
    completed_chunks: u64,
    state: TransferState,
) -> TransferProgress {
    TransferProgress {
        attachment_id: manifest.attachment_id.clone(),
        file_name: manifest.file_name.clone(),
        total_size: manifest.total_size,
        chunk_count: manifest.chunk_count,
        completed_chunks,
        state,
    }
}

fn chunk_slice(plaintext: &[u8], index: u64, chunk_size: u32) -> Option<&[u8]> {
    let start = index.checked_mul(u64::from(chunk_size))? as usize;
    if start >= plaintext.len() {
        return None;
    }
    let end = (start + chunk_size as usize).min(plaintext.len());
    Some(&plaintext[start..end])
}

fn encode(bytes: &[u8]) -> String {
    base64::Engine::encode(&base64::engine::general_purpose::STANDARD, bytes)
}

fn decode(encoded: &str) -> Option<Vec<u8>> {
    base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded).ok()
}

fn decode_fixed<const N: usize>(encoded: &str) -> Option<[u8; N]> {
    decode(encoded)?.try_into().ok()
}

fn manifest_keys(
    manifest: &AttachmentManifest,
) -> Result<([u8; ATTACHMENT_KEY_LEN], [u8; ATTACHMENT_NONCE_PREFIX_LEN]), AttachmentRuntimeError> {
    let key = decode_fixed(&manifest.key_b64)
        .ok_or_else(|| AttachmentRuntimeError::ManifestMismatch("key".into()))?;
    let nonce = decode_fixed(&manifest.nonce_prefix_b64)
        .ok_or_else(|| AttachmentRuntimeError::ManifestMismatch("nonce prefix".into()))?;
    Ok((key, nonce))
}
