//! The group wire envelopes: control, data, blob.

use std::sync::Arc;

use super::GroupSession;

use serde::{Deserialize, Serialize};

use crate::attachment_runtime::{ChunkFrame, ChunkRequest};
use crate::conversation::dm_offers::DmOffer;
use crate::conversation::runtime::ConversationRuntime;
use crate::shared_node::SharedMossNode;

/// What a group calls itself in a log line about its room.

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub(super) enum ControlEnvelope {
    KeyPackage {
        group_id: String,
        participant_id: String,
        from_device: String,
        from_fingerprint: String,
        key_package_b64: String,
    },
    Welcome {
        group_id: String,
        for_participant_id: String,
        from_fingerprint: String,
        welcome_b64: String,
        commit_b64: String,
        tree_b64: String,
    },
    Commit {
        group_id: String,
        from_fingerprint: String,
        commit_b64: String,
        /// Org groups: the author's verified roster version (ADR 0005). A
        /// commit from a not-yet-admin with a NEWER version is buffered
        /// until that roster arrives instead of being dropped.
        #[serde(default)]
        roster_version: Option<u64>,
    },
    AdminHandoff {
        group_id: String,
        from_fingerprint: String,
        next_admin_fingerprint: String,
    },
    SelfRemove {
        group_id: String,
        from_fingerprint: String,
        proposal_b64: String,
    },
    /// AttachmentManifest encrypted as an MLS application message, broadcast
    /// to every member so they can later request the chunks.
    AttachmentManifest {
        group_id: String,
        participant_id: String,
        from_device: String,
        from_fingerprint: String,
        manifest_ciphertext_b64: String,
    },
    /// A private-DM invitation aimed at one group member.
    DmOffer { group_id: String, offer: DmOffer },
    /// A member stuck behind missing commits asks for a replay (spec §7).
    ResyncRequest {
        group_id: String,
        from_fingerprint: String,
        have_epoch: u64,
    },
    /// Admin-served replay of logged commits >= the requested epoch. An
    /// empty list tells the requester the gap is unbridgeable.
    ResyncResponse {
        group_id: String,
        for_fingerprint: String,
        commits: Vec<ResyncCommit>,
    },
    /// Liveness hint published while one member types. The body — a JSON
    /// object naming the device and the sender-claimed expiry — travels
    /// MLS-encrypted exactly like an AttachmentManifest, so only group
    /// members can mint one and a mesh bystander cannot forge it. The
    /// receiver owns the expiry; old clients fail to decode the unknown
    /// variant and drop the frame.
    TypingIndicator {
        group_id: String,
        from_device: String,
        from_fingerprint: String,
        typing_ciphertext_b64: String,
    },
}

/// The MLS-encrypted body of a group `TypingIndicator` — the same shape the
/// DM hint carries, re-exported through the DM contracts.
pub(super) type GroupTypingBody = crate::private_dm_runtime::contracts::TypingBody;

/// One member currently typing, as the group snapshot names it.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct TypingMember {
    /// The member's device fingerprint — the same id the message log keys
    /// authors by, so the UI can match avatar/roster data.
    pub fingerprint: String,
    /// The typing member's display name, learned from the frame's
    /// `from_device` (and re-learned through message traffic).
    pub display_name: String,
    /// Wall-clock deadline of the hint; the receiver's clock, not the
    /// sender's claim.
    pub until_ms: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub(super) struct ResyncCommit {
    pub(super) epoch: u64,
    pub(super) commit_b64: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub(super) struct DataEnvelope {
    pub(super) group_id: String,
    pub(super) participant_id: String,
    pub(super) from_device: String,
    pub(super) from_fingerprint: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) sent_at_ms: Option<u64>,
    pub(super) ciphertext_b64: String,
}

/// Blob channel traffic. Chunk payloads are AES-GCM sealed by the
/// attachment runtime, so this envelope is plain routing metadata.
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub(super) enum BlobEnvelope {
    Request {
        participant_id: String,
        request: ChunkRequest,
    },
    Chunk {
        participant_id: String,
        frame: ChunkFrame,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct PersistedGroupSession {
    pub(super) group_id: String,
    pub(super) mesh_id: String,
    pub(super) label: Option<String>,
    pub(super) display_name: String,
    pub(super) participant_id: String,
    pub(super) device_fingerprint: String,
    pub(super) creator_fingerprint: String,
    pub(super) current_admin_fingerprint: String,
    pub(super) is_admin: bool,
    pub(super) invite_uri: Option<String>,
    pub(super) joined: bool,
    pub(super) signer_public: Vec<u8>,
    pub(super) mls_group_id: Vec<u8>,
    pub(super) listen_port: u16,
    pub(super) static_peer: Option<String>,
    #[serde(default)]
    pub(super) org_pubkey: Option<String>,
}

pub struct PrivateGroupRuntime {
    // The one moss node this process runs. Every group is a room on it, not a
    // node of its own — see `shared_node` for why more than one is actively
    // harmful.
    pub(super) shared_node: Arc<SharedMossNode>,
    pub(super) groups: ConversationRuntime<GroupSession>,
}
