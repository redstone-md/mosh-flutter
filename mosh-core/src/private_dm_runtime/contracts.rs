use serde::{Deserialize, Serialize};

use crate::conversation::message_log::{ConversationMessage, LogError};
use crate::mls_crypto::MlsCryptoError;
use crate::outbound_delivery::MessageDeliveryMeta;
pub use crate::outbound_delivery::MessageDeliveryStatus;
use flutter_rust_bridge::frb;

// Shapes a DM shares with the other kinds. They live beside the shared code
// that builds them; a DM only re-exports them so `private_dm_runtime::X` keeps
// naming the same type it always did.
pub use super::transport::PeerTransport;
pub use crate::conversation::attachments::{
    AttachmentDescriptor, AttachmentSendResult, AttachmentState, AttachmentView,
};
pub use crate::conversation::dm_offers::DmOffer;
pub use crate::conversation::mesh::{MeshInfo, PeerDetail, SnapshotEvent};

/// Where a DM stands, as proven by the other side. `Connected` is only
/// reached on an MLS-authenticated frame from the counterpart and only left
/// when the counterpart drops out of reach.
#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DmSessionState {
    /// Invite created or accepted; nothing from the counterpart yet.
    Pending,
    /// The counterpart's handshake frame arrived, or it was connected and is
    /// out of reach now. Nothing authenticated has come back since.
    Handshaking,
    /// The counterpart answered with an authenticated frame.
    Connected,
}

/// What the last request to reach the counterpart answered, for the
/// diagnostics card. moss keeps retrying a requested target on its own, so
/// "requested" is the good outcome; a failure means moss would not take the
/// request at all, and the runtime asks again on its next tick. The error
/// text goes to the log, where it can be read in full.
#[frb(non_opaque)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectOutcome {
    Requested,
    Failed,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartSessionRequest {
    pub display_name: String,
    pub listen_port: u16,
    pub static_peer: Option<String>,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize)]
pub struct InviteCreated {
    pub invite_uri: String,
    pub session_id: String,
    pub mesh_id: String,
    pub fingerprint: String,
    pub listen_address: String,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcceptInviteRequest {
    pub invite_uri: String,
    pub display_name: String,
    pub listen_port: u16,
    pub static_peer: Option<String>,
}

/// The MLS-encrypted body of a `TypingIndicator` (DM and group share it).
/// The device name lets the receiver label the hint with an authenticated
/// name; `until_ms` is the sender's own claim and stays advisory — the
/// receiver stamps the hint with its own clock so a skewed sender cannot
/// stretch it.
#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TypingBody {
    pub device: String,
    pub until_ms: u64,
}

/// The MLS-encrypted body of a `ReadReceipt`: the id of ONE message the
/// sender has seen. One id per frame (the ack shape) keeps a lost receipt
/// re-sendable as the same single-frame problem a lost ack already is — a
/// batch would lose or re-deliver every id together. Anything else in the
/// frame is the transport's business; the receipt is only this id.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadReceiptBody {
    pub message_id: String,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize)]
pub struct SessionSnapshot {
    pub session_id: String,
    pub mesh_id: String,
    pub role: String,
    /// The local device's own display name.
    pub display_name: String,
    /// The remote peer's display name, learned from inbound messages/control.
    /// Empty until the first inbound frame from the peer is seen.
    pub peer_display_name: String,
    pub state: DmSessionState,
    /// How the counterpart is reachable through moss right now.
    pub transport: PeerTransport,
    /// The counterpart's moss peer id, once a handshake frame carried it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer_moss_id: Option<String>,
    /// What the last request to reach the counterpart answered.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_connect_outcome: Option<ConnectOutcome>,
    pub invite_uri: Option<String>,
    pub fingerprint: String,
    pub messages: Vec<ChatMessage>,
    pub attachments: Vec<AttachmentView>,
    pub mesh: Option<MeshInfo>,
    pub events: Vec<SnapshotEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_call: Option<PendingCall>,
    /// Wall-clock deadline of the peer's typing hint, if one stands. Absent
    /// when the peer is not typing; a poll past the deadline simply stops
    /// carrying the field.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peer_typing_until_ms: Option<u64>,
    /// Present while the local user is placing a call and waiting for the peer
    /// to answer (caller-side "ringing" state).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub outgoing_call: Option<OutgoingCall>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_call: Option<ActiveCall>,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize)]
pub struct SessionListSnapshot {
    pub sessions: Vec<SessionSnapshot>,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize)]
pub struct CloseSessionResult {
    pub session_id: String,
    pub closed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub from_device: String,
    pub body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_at_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attachment: Option<AttachmentDescriptor>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub call_event: Option<CallEvent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_status: Option<MessageDeliveryStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retryable: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retry_count: Option<u32>,
    /// The [[Read receipt]] on the user's OWN message: `Some(true)` once the
    /// counterpart's authenticated receipt landed, absent until then (and
    /// always absent for the counterpart's messages — they have nothing to
    /// learn about their own reads). Additive and skip-when-none, so old
    /// snapshots and old history rows stay valid.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub read: Option<bool>,
}

impl ConversationMessage for ChatMessage {
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

    /// A DM has two participants and no fingerprint on the message, so the
    /// sender's device name is what tells the two apart.
    fn author(&self) -> &str {
        &self.from_device
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
pub struct PendingCall {
    pub call_id: String,
    pub from_device: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct OutgoingCall {
    pub call_id: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ActiveCall {
    pub call_id: String,
    /// "caller" or "callee" — drives the nonce direction bit.
    pub direction: String,
    pub key_b64: String,
    pub nonce_prefix_b64: String,
    /// Unix millis when the call became Active; the running timer
    /// renders from this anchor.
    pub started_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallEvent {
    /// "completed" or "missed".
    pub kind: String,
    pub duration_ms: u64,
    pub call_id: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CallStarted {
    pub session_id: String,
    pub call_id: String,
    pub key_b64: String,
    pub nonce_prefix_b64: String,
}

/// Body of an MLS-encrypted CallOffer. Never crosses the wire in the clear:
/// the runtime serialises it to JSON, encrypts via the session's MLS
/// application-message key, and ships the ciphertext in
/// `ControlEnvelope::CallOffer::offer_ciphertext_b64`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CallOfferBody {
    pub key_b64: String,
    pub nonce_prefix_b64: String,
}

#[frb(non_opaque)]
#[derive(Debug, Clone, Serialize)]
pub struct SendMessageResult {
    pub session_id: String,
    pub state: DmSessionState,
    pub ciphertext_bytes: usize,
    pub message_id: String,
    pub sent_at_ms: u64,
    pub delivery_status: MessageDeliveryStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_error: Option<String>,
}

#[derive(Debug)]
pub enum PrivateDmRuntimeError {
    Moss(String),
    OpenMls(String),
    Codec(String),
    InvalidInvite(String),
    NotReady,
    MissingSession,
    MissingMessage(String),
    DuplicateSession(String),
    Attachment(String),
    MissingAttachment(String),
    /// At-rest persistence layer failure (encrypted redb store or the OS
    /// keychain backing the DEK). Surfaced as a distinct variant -- not
    /// folded into `Moss` -- so the fail-closed path (DEK unavailable while a
    /// DB exists, corrupt DEK, etc.) is identifiable in diagnostics without
    /// parsing the message text. First wired consumer: `api::private_dm`
    /// `ensure_runtime` (ADR 0011 SecureSecretStore).
    Persistence(String),
}

impl std::fmt::Display for PrivateDmRuntimeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Moss(error) => write!(formatter, "Moss error: {error}"),
            Self::OpenMls(error) => write!(formatter, "OpenMLS error: {error}"),
            Self::Codec(error) => write!(formatter, "codec error: {error}"),
            Self::InvalidInvite(error) => write!(formatter, "invalid invite: {error}"),
            Self::NotReady => write!(formatter, "private DM session is not ready"),
            Self::MissingSession => write!(formatter, "private DM session is missing"),
            Self::MissingMessage(id) => write!(formatter, "private DM message is missing: {id}"),
            Self::DuplicateSession(id) => {
                write!(formatter, "private DM session already exists: {id}")
            }
            Self::Attachment(error) => write!(formatter, "attachment error: {error}"),
            Self::MissingAttachment(id) => {
                write!(formatter, "attachment not found: {id}")
            }
            Self::Persistence(error) => {
                write!(formatter, "persistence error: {error}")
            }
        }
    }
}

impl std::error::Error for PrivateDmRuntimeError {}

impl From<MlsCryptoError> for PrivateDmRuntimeError {
    fn from(error: MlsCryptoError) -> Self {
        match error {
            MlsCryptoError::OpenMls(message) => Self::OpenMls(message),
            MlsCryptoError::Codec(message) => Self::Codec(message),
            MlsCryptoError::NotReady => Self::NotReady,
        }
    }
}

impl From<crate::conversation::transfer::TransferError> for PrivateDmRuntimeError {
    fn from(error: crate::conversation::transfer::TransferError) -> Self {
        match error {
            crate::conversation::transfer::TransferError::Bytes(message) => {
                Self::Attachment(message)
            }
            crate::conversation::transfer::TransferError::Slot(error) => error.into(),
        }
    }
}

impl From<LogError> for PrivateDmRuntimeError {
    fn from(error: LogError) -> Self {
        match error {
            LogError::Missing(id) => Self::MissingMessage(id),
            LogError::Codec(error) => Self::Codec(error),
        }
    }
}

impl From<crate::conversation::attachments::SlotError> for PrivateDmRuntimeError {
    fn from(error: crate::conversation::attachments::SlotError) -> Self {
        match error {
            crate::conversation::attachments::SlotError::Missing(id) => Self::MissingAttachment(id),
            other => Self::Attachment(other.to_string()),
        }
    }
}

impl From<crate::persistence::PersistenceError> for PrivateDmRuntimeError {
    fn from(error: crate::persistence::PersistenceError) -> Self {
        Self::Persistence(error.to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistedSession {
    pub role_is_alice: bool,
    pub display_name: String,
    pub participant_id: String,
    pub session_id: String,
    pub mesh_id: String,
    pub fingerprint: String,
    pub invite_uri: Option<String>,
    pub signer_public: Vec<u8>,
    pub group_id: Vec<u8>,
    pub listen_port: u16,
    pub static_peer: Option<String>,
    /// The counterpart's moss peer id, learned from its KeyPackage/Welcome.
    /// Persisted because it is the ONLY thing separating our peer from the
    /// unrelated world peers on the shared substrate: a restored session
    /// without it cannot tell whether the counterpart is online, cannot dial
    /// it, and cannot address a relayed send. Defaulted so records written
    /// before this field existed still load.
    #[serde(default)]
    pub peer_moss_id: Option<String>,
    /// Message ids the counterpart has authenticated a read of, persisted so
    /// a restart does not re-ask (a re-asked receipt is a frame the peer has
    /// to answer again for something it already told us). Defaulted so
    /// records written before this field existed still load. Pruned to the
    /// last `READ_HISTORY_KEEP` ids on write, so the record cannot grow
    /// without bound.
    #[serde(default)]
    pub read_message_ids: Vec<String>,
}

/// How many read ids a session record keeps (the same bound the runtime
/// applies in memory; re-declared here so the serialized shape's contract
/// lives beside the field).
pub const READ_HISTORY_KEEP: usize = 512;

/// Keeps the LAST ids (the newest reads) and drops the rest, once the list
/// outgrows the cap. Order is preserved for the ids that stay.
pub fn prune_read_ids(ids: &[String]) -> Vec<String> {
    let overflow = ids.len().saturating_sub(READ_HISTORY_KEEP);
    ids.iter().skip(overflow).cloned().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::conversation::history::StoredMessage;

    #[test]
    fn persisted_message_round_trips_attachment_and_call() {
        let msg = ChatMessage {
            from_device: "alice".into(),
            body: String::new(),
            message_id: Some("123-000000".into()),
            sent_at_ms: Some(123),
            attachment: Some(AttachmentDescriptor {
                attachment_id: "a1".into(),
                content_hash: "abc123".into(),
                file_name: "photo.bin".into(),
                mime: "image/png".into(),
                total_size: 42,
                thumbnail_b64: None,
                voice: None,
            }),
            call_event: Some(CallEvent {
                kind: "completed".into(),
                duration_ms: 9000,
                call_id: "c1".into(),
            }),
            delivery_status: Some(MessageDeliveryStatus::Failed),
            delivery_error: Some("publish failed".into()),
            retryable: Some(true),
            retry_count: Some(2),
            read: None,
        };
        let pm = StoredMessage {
            conversation_id: "conv".into(),
            sent_at_ms: 123,
            message_id: "123-000000".into(),
            message: msg,
            attachment_manifest: None,
        };
        let bytes = serde_json::to_vec(&pm).unwrap();
        let back: StoredMessage<ChatMessage> = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(back.message.attachment.unwrap().file_name, "photo.bin");
        let ce = back.message.call_event.unwrap();
        assert_eq!(ce.kind, "completed");
        assert_eq!(ce.duration_ms, 9000);
        assert_eq!(back.message.retry_count, Some(2));
        assert_eq!(back.message.read, None);
    }

    // The cap keeps a long-lived DM's record bounded: past the cap, the
    // NEWEST ids are the ones that stay.
    #[test]
    fn pruned_read_ids_keep_the_newest() {
        let ids: Vec<String> = (0..READ_HISTORY_KEEP + 3)
            .map(|i| format!("m{i:06}"))
            .collect();
        let kept = prune_read_ids(&ids);
        assert_eq!(kept.len(), READ_HISTORY_KEEP, "the cap holds");
        assert_eq!(kept[0], "m000003", "the oldest ids are dropped");
        assert_eq!(
            kept.last().map(String::as_str),
            Some(format!("m{:06}", READ_HISTORY_KEEP + 2).as_str()),
            "the newest id survives"
        );
    }

    // The read-receipt persistence story: `read` and `read_message_ids` are
    // additive `#[serde(default)]` fields, so a session record a build
    // before the feature wrote still loads — with no read state.
    #[test]
    fn a_legacy_record_without_read_state_still_loads() {
        let legacy = serde_json::json!({
            "role_is_alice": true,
            "display_name": "Alice",
            "participant_id": "p",
            "session_id": "s",
            "mesh_id": "m",
            "fingerprint": "f",
            "invite_uri": null,
            "signer_public": [1, 2, 3],
            "group_id": [],
            "listen_port": 0,
            "static_peer": null
        });
        let record: PersistedSession =
            serde_json::from_value(legacy).expect("a pre-receipts record still loads");
        assert_eq!(record.peer_moss_id, None);
        assert!(
            record.read_message_ids.is_empty(),
            "no read state is persisted yet"
        );
    }
}
