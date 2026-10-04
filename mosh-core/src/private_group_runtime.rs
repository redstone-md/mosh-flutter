use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::attachment_runtime::{AttachmentManifest, OutgoingAttachment, StreamRange, VoiceMeta};
use crate::attachment_store::AttachmentStore;
use crate::commit_sequencer::{CommitSequencer, Disposition};
use crate::conversation::attachments::{
    AttachmentDescriptor, AttachmentSendResult, AttachmentView, SlotError,
};
use crate::conversation::dedup::SeenFrames;
use crate::conversation::dm_offers::{DmOffer, DmOffers};
use crate::conversation::history::Restore;
use crate::conversation::mesh::{self, MeshInfo, SnapshotEvent};
use crate::conversation::message_log::{ConversationMessage, LogError, MessageLog};
use crate::conversation::outbound::{OnSent, Outbox, Prepared};
use crate::conversation::runtime::{self, ConversationRuntime, ConversationSession};
use crate::conversation::transfer::{Transfer, TransferError};
use crate::conversation::{decode, encode, now_ms};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::inbox;
use crate::mls_crypto::{AddOutcome, MlsCryptoError, MlsSessionCrypto};
use crate::moss_ffi::{MossFfiRuntime, MossNode, MossReceivedMessage};
use crate::org_envelope::{self, OrgContext, OrgSigned};
use crate::org_roster::{self, Roster};
use crate::org_signing;
use crate::outbound_delivery::{MessageDeliveryMeta, MessageDeliveryStatus, OutboundAttemptRecord};
use crate::persistence::{Persistence, GROUP_HISTORY};
use crate::shared_node::SharedMossNode;
use ed25519_dalek::SigningKey;

/// What a group calls itself in a log line about its room.
pub(crate) const KIND: &str = "group";
const CONTROL_CHANNEL_PREFIX: &str = "group-control/";
const DATA_CHANNEL_PREFIX: &str = "group-data/";
const BLOB_CHANNEL_PREFIX: &str = "group-blob/";

// The typing cadence, expiry window, and pinned event code live in
// `conversation::typing`, shared with the DM side.
use crate::conversation::typing::{self as typing_shared, TypingGate};

/// The group's own inbound queue, claimed once for the process.
fn group_inbox() -> &'static inbox::Inbox {
    static INBOX: std::sync::OnceLock<inbox::Inbox> = std::sync::OnceLock::new();
    INBOX.get_or_init(|| {
        inbox::register(|channel| {
            channel.starts_with(CONTROL_CHANNEL_PREFIX)
                || channel.starts_with(DATA_CHANNEL_PREFIX)
                || channel.starts_with(BLOB_CHANNEL_PREFIX)
        })
    })
}
pub(crate) const INVITE_PREFIX: &str = "mosh://group";
pub(crate) const MAX_LABEL_LEN: usize = 64;
pub(crate) const MAX_BODY_LEN: usize = 4096;
pub(crate) const INVITE_FINGERPRINT_LEN: usize = 32;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGroupRequest {
    pub label: Option<String>,
    pub display_name: String,
    pub listen_port: u16,
    pub static_peer: Option<String>,
    /// Set = org-bound group (ADR 0008): peer-id credentials, enveloped
    /// control traffic, roster-derived authority and revocation.
    #[serde(default)]
    pub org_pubkey: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinGroupRequest {
    pub invite_uri: String,
    pub display_name: String,
    /// Conveyed by the OrgGroupOffer that carried the invite (spec §5).
    #[serde(default)]
    pub org_pubkey: Option<String>,
    pub listen_port: u16,
    pub static_peer: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct GroupCreated {
    pub group_id: String,
    pub mesh_id: String,
    pub invite_uri: String,
    pub fingerprint: String,
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupMessage {
    pub from_device: String,
    pub from_fingerprint: String,
    pub body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_at_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
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

impl ConversationMessage for GroupMessage {
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
pub struct GroupSnapshot {
    pub group_id: String,
    pub mesh_id: String,
    pub label: Option<String>,
    pub display_name: String,
    pub device_fingerprint: String,
    pub creator_fingerprint: String,
    pub is_admin: bool,
    pub state: String,
    pub member_count: usize,
    pub invite_uri: Option<String>,
    pub messages: Vec<GroupMessage>,
    pub attachments: Vec<AttachmentView>,
    pub dm_offers: Vec<DmOffer>,
    pub mesh: Option<MeshInfo>,
    pub events: Vec<SnapshotEvent>,
    /// A commit gap could not be bridged by resync; the member must rejoin.
    pub needs_rejoin: bool,
    /// Some = org-bound group (ADR 0008).
    pub org_pubkey: Option<String>,
    /// Leaf credential identities; on org groups these are moss peer-ids,
    /// letting the UI diff the roster against group membership.
    pub member_peer_ids: Vec<String>,
    /// Members currently typing, one entry each with the deadline the
    /// receiver stamped. Empty when nobody is.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub typing_members: Vec<TypingMember>,
}

#[derive(Debug, Clone, Serialize)]
pub struct GroupListSnapshot {
    pub groups: Vec<GroupSnapshot>,
}

#[derive(Debug, Clone, Serialize)]
pub struct GroupSendResult {
    pub group_id: String,
    pub bytes: usize,
    pub message_id: String,
    pub sent_at_ms: u64,
    pub delivery_status: MessageDeliveryStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct GroupLeaveResult {
    pub group_id: String,
    pub closed: bool,
}

mod error;
pub use error::*;
pub(crate) mod wire_types;
pub use wire_types::PrivateGroupRuntime;
pub(crate) use wire_types::*;

use session::GroupSession;

struct RosterLaggedCommit {
    roster_version: u64,
    sender_peer_id: String,
    commit_b64: String,
}

/// Bounds the lag buffer against spam; genuine lag is 1–2 commits deep.
pub(crate) const ROSTER_LAG_CAP: usize = 16;
/// Max plausible roster-version lead a lag-buffered commit may claim.
pub(crate) const ROSTER_LAG_HORIZON: u64 = 64;

impl PrivateGroupRuntime {
    /// Test/probe constructor shape kept for symmetry with the DM runtime's
    /// `from_shared`; the api facade builds groups through `from_shared_node`.
    #[allow(dead_code)]
    pub fn from_shared(
        moss: Arc<MossFfiRuntime>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        Self::from_shared_node(SharedMossNode::new(moss), attachment_store, persistence)
    }

    /// The constructor a real client uses: every runtime in the process is
    /// handed the SAME holder, so groups share their node with DMs, channels
    /// and orgs. `from_shared` mints a private holder, which is what tests
    /// running two peers in one process need.
    pub fn from_shared_node(
        shared_node: Arc<SharedMossNode>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        // Claim the group channels before any node of ours can start; see
        // `crate::inbox`.
        group_inbox();
        Self {
            shared_node,
            groups: ConversationRuntime::new(attachment_store, persistence, GROUP_HISTORY),
        }
    }

    /// Reaching for one open group, the way every facade method starts.
    fn group_mut(&mut self, group_id: &str) -> Result<&mut GroupSession, PrivateGroupError> {
        self.groups
            .get_mut(group_id)
            .ok_or_else(|| PrivateGroupError::MissingGroup(group_id.to_string()))
    }

    /// Take a reference to the shared node and put this group's room on it.
    fn open_group_room(
        &mut self,
        mesh_id: &str,
        group_id: &str,
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<Arc<MossNode>, PrivateGroupError> {
        runtime::open_room(
            &self.shared_node,
            mesh_id,
            &group_channels(group_id),
            listen_port,
            static_peer,
        )
        .map_err(PrivateGroupError::Moss)
    }

    pub fn poll(&mut self, group_id: &str) -> Result<GroupSnapshot, PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail_logged(KIND);
        let session = self.group_mut(group_id)?;
        Ok(session.snapshot())
    }

    pub fn list(&mut self) -> Result<GroupListSnapshot, PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail_logged(KIND);
        let mut groups: Vec<GroupSnapshot> = self
            .groups
            .values_mut()
            .map(GroupSession::snapshot)
            .collect();
        groups.sort_by(|a, b| a.group_id.cmp(&b.group_id));
        Ok(GroupListSnapshot { groups })
    }

    fn drain_inbound(&mut self) -> Result<(), PrivateGroupError> {
        let inbound = group_inbox().drain();
        for message in inbound {
            let group_id = match channel_group_id(&message.channel) {
                Some(gid) => gid.to_string(),
                None => continue,
            };
            if let Some(session) = self.groups.get_mut(&group_id) {
                // A single bad inbound frame must never abort the drain — it
                // would also fail the caller (send/poll/list drain first). After
                // a restart the in-memory dedup set is empty, so the mesh
                // re-delivers already-consumed MLS messages whose decrypt fails
                // ("secret deleted for forward secrecy"); drop and keep going,
                // mirroring the DM runtime.
                if let Err(error) = session.handle_moss_message(message) {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::FRAME,
                        &group_id,
                        &format!("dropping inbound group frame: {error}"),
                    );
                }
            }
        }
        for session in self.groups.values_mut() {
            session.pump_attachment_requests();
            // ADR 0005: a roster change may legitimize lag-buffered commits.
            session.sync_roster_state();
        }
        Ok(())
    }
}

// The session's own machinery, split by concern: publishing, org authority,
// commits, channels, snapshot. All `impl GroupSession` on the same struct.
mod commits;
mod control;
mod data;
mod lifecycle;
mod org_gate;
mod pending_join;
mod rehydrate;
mod snapshot;
mod wires;

#[cfg(test)]
#[path = "private_group_runtime/runtime_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "private_group_runtime/durability_tests.rs"]
mod durability_tests;

use sequencing::{
    absorb_resync_commits, log_group_commit, sequence_commit, successor_of, SequenceOutcome,
};

use invite::*;

mod actions;
mod close;
mod invite;
mod outbound;
mod sequencing;
mod session;

use wires::*;
