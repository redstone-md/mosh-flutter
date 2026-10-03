use super::{AttachmentCryptoError, MAX_ATTACHMENT_SIZE};
use serde::{Deserialize, Serialize};

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
