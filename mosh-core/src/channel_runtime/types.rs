//! The channel wire types, persisted record shape, and error.

use super::*;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelMessage {
    pub from_device: String,
    pub from_fingerprint: String,
    pub body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_at_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attachment: Option<AttachmentDescriptor>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_status: Option<MessageDeliveryStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retryable: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retry_count: Option<u32>,
}

impl ConversationMessage for ChannelMessage {
    fn message_id(&self) -> Option<&str> {
        self.message_id.as_deref()
    }

    fn set_message_id(&mut self, message_id: String) {
        self.message_id = Some(message_id);
    }

    fn sent_at_ms(&self) -> Option<u64> {
        self.sent_at_ms
    }

    fn set_sent_at_ms(&mut self, sent_at_ms: u64) {
        self.sent_at_ms = Some(sent_at_ms);
    }

    fn body(&self) -> &str {
        &self.body
    }

    fn author(&self) -> &str {
        &self.from_fingerprint
    }

    fn attachment(&self) -> Option<&AttachmentDescriptor> {
        self.attachment.as_ref()
    }

    fn set_delivery(&mut self, delivery: MessageDeliveryMeta) {
        self.delivery_status = delivery.delivery_status;
        self.delivery_error = delivery.delivery_error;
        self.retryable = delivery.retryable;
        self.retry_count = delivery.retry_count;
    }

    fn delivery_status(&self) -> Option<MessageDeliveryStatus> {
        self.delivery_status
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ChannelSnapshot {
    pub name: String,
    pub topic: String,
    pub mesh_id: String,
    pub display_name: String,
    pub device_fingerprint: String,
    pub messages: Vec<ChannelMessage>,
    pub attachments: Vec<AttachmentView>,
    pub dm_offers: Vec<DmOffer>,
    pub mesh: Option<MeshInfo>,
    pub events: Vec<SnapshotEvent>,
}

/// Blob-channel traffic for public channels. There is no MLS layer here,
/// so the manifest (and its AES key) travels in the clear: a public
/// channel offers integrity, not confidentiality. Chunk payloads are
/// still AES-GCM sealed by the attachment runtime.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub(super) enum ChannelBlobEnvelope {
    Manifest {
        from_device: String,
        from_fingerprint: String,
        manifest: AttachmentManifest,
    },
    Request {
        from_fingerprint: String,
        request: ChunkRequest,
    },
    Chunk {
        from_fingerprint: String,
        frame: ChunkFrame,
    },
    /// A private-DM invitation aimed at one channel member.
    DmOffer { offer: DmOffer },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct PersistedChannelSession {
    pub(super) name: String,
    pub(super) topic: String,
    pub(super) blob_topic: String,
    pub(super) mesh_id: String,
    pub(super) display_name: String,
    pub(super) device_fingerprint: String,
    pub(super) listen_port: u16,
    pub(super) static_peer: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ChannelListSnapshot {
    pub channels: Vec<ChannelSnapshot>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ChannelSendResult {
    pub name: String,
    pub bytes: usize,
    pub message_id: String,
    pub sent_at_ms: u64,
    pub delivery_status: MessageDeliveryStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ChannelLeaveResult {
    pub name: String,
    pub closed: bool,
}

#[derive(Debug)]
pub enum ChannelRuntimeError {
    Moss(String),
    Codec(String),
    InvalidName(String),
    BodyTooLarge,
    MissingChannel(String),
    MissingMessage(String),
    DuplicateChannel(String),
    Attachment(String),
    MissingAttachment(String),
}

impl std::fmt::Display for ChannelRuntimeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Moss(error) => write!(formatter, "Moss error: {error}"),
            Self::Codec(error) => write!(formatter, "codec error: {error}"),
            Self::InvalidName(name) => write!(formatter, "invalid channel name: {name}"),
            Self::BodyTooLarge => write!(formatter, "channel message too large"),
            Self::MissingChannel(name) => write!(formatter, "channel not joined: {name}"),
            Self::MissingMessage(id) => write!(formatter, "channel message missing: {id}"),
            Self::DuplicateChannel(name) => write!(formatter, "already joined channel: {name}"),
            Self::Attachment(error) => write!(formatter, "attachment error: {error}"),
            Self::MissingAttachment(id) => write!(formatter, "attachment not found: {id}"),
        }
    }
}

impl std::error::Error for ChannelRuntimeError {}

impl From<TransferError> for ChannelRuntimeError {
    fn from(error: TransferError) -> Self {
        match error {
            TransferError::Bytes(message) => Self::Attachment(message),
            TransferError::Slot(error) => error.into(),
        }
    }
}

impl From<LogError> for ChannelRuntimeError {
    fn from(error: LogError) -> Self {
        match error {
            LogError::Missing(id) => Self::MissingMessage(id),
            LogError::Codec(error) => Self::Codec(error),
        }
    }
}

impl From<SlotError> for ChannelRuntimeError {
    fn from(error: SlotError) -> Self {
        match error {
            SlotError::Missing(id) => Self::MissingAttachment(id),
            other => Self::Attachment(other.to_string()),
        }
    }
}

pub struct ChannelRuntime {
    // The one moss node this process runs. Every joined channel is a room on
    // it, not a node of its own — see `shared_node` for why more than one is
    // actively harmful.
    pub(super) shared_node: Arc<SharedMossNode>,
    pub(super) channels: ConversationRuntime<ChannelSession>,
}
