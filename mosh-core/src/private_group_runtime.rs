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
mod wire_types;
pub(super) use wire_types::*;

struct GroupSession {
    group_id: String,
    mesh_id: String,
    label: Option<String>,
    display_name: String,
    participant_id: String,
    device_fingerprint: String,
    creator_fingerprint: String,
    current_admin_fingerprint: String,
    is_admin: bool,
    invite_uri: Option<String>,
    joined: bool,
    listen_port: u16,
    static_peer: Option<String>,
    node: Arc<MossNode>,
    crypto: MlsSessionCrypto,
    messages: MessageLog<GroupMessage>,
    seen: SeenFrames,
    // Epoch-ordered commit admission: dedups gossip duplicates and the
    // joiner's Welcome-carried admission commit, buffers out-of-order commits,
    // reports gaps for resync. Unbounded like its predecessor set — commits
    // only fire on membership change (rare).
    sequencer: CommitSequencer,
    // Clone of the runtime's store: applied/produced commits land in
    // group_commit_log so the admin can serve ResyncRequests.
    persistence: Option<Arc<Persistence>>,
    // Set when a commit gap could not be bridged by resync; surfaced to the
    // UI ("rejoin needed") instead of silently desyncing.
    needs_rejoin: bool,
    control_channel: String,
    data_channel: String,
    blob_channel: String,
    transfer: Transfer,
    outbound_attempts: HashMap<String, OutboundAttemptRecord>,
    dm_offers: DmOffers,
    /// Org binding (ADR 0008). Some = control traffic is enveloped, the MLS
    /// credential is the moss peer-id and authority derives from the roster.
    org_pubkey: Option<String>,
    /// Node identity key for enveloping; present iff `org_pubkey` is.
    org_signer: Option<SigningKey>,
    /// Verified-roster cache keyed by the raw stored bytes, so repeated
    /// control messages don't re-verify an unchanged roster.
    roster_cache: Option<(Vec<u8>, Roster)>,
    /// Commits from authors ahead of our roster (ADR 0005), retried on
    /// every roster change and dropped once the author is provably not an
    /// admin at their claimed version.
    roster_lag: Vec<RosterLaggedCommit>,
    /// Roster version at the last lag-retry, so a change triggers exactly
    /// one retry pass.
    last_roster_version_seen: Option<u64>,
    /// Fingerprint → wall-clock deadline of that member's typing hint. A
    /// refresh inside the window renews the entry; silence lets it lapse.
    typing_members: HashMap<String, u64>,
    /// Fingerprint → the member's display name, learned from the
    /// authenticated frames that carry it (typing hints, messages). The
    /// roster view reads names from here instead of re-deriving them.
    member_names: HashMap<String, String>,
    /// The send-cadence gate for this member's own TypingIndicator
    /// publishes.
    typing_gate: TypingGate,
}

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
    /// Encrypts a file, stores the sender's copy, and broadcasts the manifest
    /// to every group member over the MLS-protected control channel.
    pub fn send_attachment(
        &mut self,
        group_id: &str,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        let result = session.send_attachment(file_name, mime, bytes, thumbnail, voice)?;
        self.groups.persist_tail();
        Ok(result)
    }

    pub fn download_attachment(
        &mut self,
        group_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        session.transfer.start_download(attachment_id)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        group_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        Ok(session.transfer.cancel(attachment_id)?)
    }

    /// Publishes a private-DM invitation aimed at one group member.
    pub fn send_dm_offer(
        &mut self,
        group_id: &str,
        target_fingerprint: String,
        invite_uri: String,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        let offer = DmOffers::mint(
            session.display_name.clone(),
            session.device_fingerprint.clone(),
            target_fingerprint,
            invite_uri,
        );
        session.publish_control(&ControlEnvelope::DmOffer {
            group_id: session.group_id.clone(),
            offer,
        })
    }

    /// Leaving an org closes every group bound to it — otherwise the
    /// sessions would freeze (roster gone ⇒ no commit is ever authorized
    /// again) while still appearing live.
    pub fn close_org_groups(&mut self, org_pubkey: &str) {
        let bound: Vec<String> = self
            .groups
            .values()
            .filter(|session| session.org_pubkey.as_deref() == Some(org_pubkey))
            .map(|session| session.group_id.clone())
            .collect();
        for group_id in bound {
            if let Err(error) = self.close(&group_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::ROOM,
                    &group_id,
                    &format!("close on org leave failed: {error}"),
                );
            }
        }
    }

    pub fn dismiss_dm_offer(
        &mut self,
        group_id: &str,
        offer_id: &str,
    ) -> Result<(), PrivateGroupError> {
        let session = self.group_mut(group_id)?;
        session.dm_offers.dismiss(offer_id);
        Ok(())
    }

    /// Serves a byte range for streaming playback of a group attachment.
    pub fn stream_attachment_range(
        &mut self,
        group_id: &str,
        attachment_id: &str,
        start: u64,
        end: u64,
    ) -> Result<StreamRange, PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        let outcome = session.transfer.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }

    pub fn send(
        &mut self,
        group_id: &str,
        body: String,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        if body.len() > MAX_BODY_LEN {
            return Err(PrivateGroupError::BodyTooLarge);
        }
        self.drain_inbound()?;
        let prepared = {
            let session = self.group_mut(group_id)?;
            if !session.joined {
                return Err(PrivateGroupError::NotReady);
            }
            let ciphertext = session.crypto.encrypt(body.as_bytes())?;
            let message = session.messages.stamp(GroupMessage {
                from_device: session.display_name.clone(),
                from_fingerprint: session.device_fingerprint.clone(),
                body,
                message_id: None,
                sent_at_ms: None,
                attachment: None,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
            });
            let envelope = DataEnvelope {
                group_id: session.group_id.clone(),
                participant_id: session.participant_id.clone(),
                from_device: session.display_name.clone(),
                from_fingerprint: session.device_fingerprint.clone(),
                message_id: message.message_id.clone(),
                sent_at_ms: message.sent_at_ms,
                ciphertext_b64: encode(&ciphertext),
            };
            let payload = serde_json::to_vec(&envelope)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
            let owned_group_id = session.group_id.clone();
            session
                .outbox()
                .open(message, owned_group_id, payload, ciphertext.len())?
        };
        let result = self.publish_prepared(group_id, prepared, true)?;
        self.groups.persist_tail();
        Ok(result)
    }

    pub fn retry_message(
        &mut self,
        group_id: &str,
        message_id: &str,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        self.drain_inbound()?;
        let prepared = {
            let session = self.group_mut(group_id)?;
            session.outbox().reopen(message_id)?
        };
        self.publish_prepared(group_id, prepared, false)
    }

    /// Signals "I am typing" in one group, driven by the composer's input.
    /// The per-keystroke call is folded down to the refresh cadence inside
    /// the session; a publish the transport refuses is retried on the next
    /// call (no error to the composer — a dropped hint only delays a hint).
    pub fn typing_signal(&mut self, group_id: &str) -> Result<(), PrivateGroupError> {
        self.drain_inbound()?;
        let session = self.group_mut(group_id)?;
        session.publish_typing(now_ms());
        Ok(())
    }

    /// Publishes a prepared send on the group's data channel and writes down
    /// how it went. A group has no acknowledgement, so the attempt record is
    /// gone as soon as the frame is on the wire.
    fn publish_prepared(
        &mut self,
        group_id: &str,
        prepared: Prepared,
        persist_snapshot: bool,
    ) -> Result<GroupSendResult, PrivateGroupError> {
        self.groups
            .persist_send(group_id, &prepared.message_id, persist_snapshot);
        let publish = {
            let session = self
                .groups
                .get(group_id)
                .ok_or_else(|| PrivateGroupError::MissingGroup(group_id.to_string()))?;
            session
                .node
                .publish_room(&session.mesh_id, &session.data_channel, &prepared.payload)
                .map_err(|error| PrivateGroupError::Moss(error.to_string()))
        };
        let (group_id_owned, settled) = {
            let session = self.group_mut(group_id)?;
            let group_id_owned = session.group_id.clone();
            let settled = session.outbox().settle(
                &prepared.message_id,
                publish.map_err(|error| error.to_string()),
                OnSent::Forget,
            )?;
            (group_id_owned, settled)
        };
        self.groups
            .persist_send(group_id, &prepared.message_id, false);
        Ok(GroupSendResult {
            group_id: group_id_owned,
            bytes: prepared.ciphertext_bytes,
            message_id: prepared.message_id,
            sent_at_ms: prepared.sent_at_ms,
            delivery_status: settled.status,
            delivery_error: settled.error,
        })
    }

    pub fn poll(&mut self, group_id: &str) -> Result<GroupSnapshot, PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail();
        let session = self.group_mut(group_id)?;
        Ok(session.snapshot())
    }

    pub fn list(&mut self) -> Result<GroupListSnapshot, PrivateGroupError> {
        self.drain_inbound()?;
        self.groups.persist_tail();
        let mut groups: Vec<GroupSnapshot> = self
            .groups
            .values_mut()
            .map(GroupSession::snapshot)
            .collect();
        groups.sort_by(|a, b| a.group_id.cmp(&b.group_id));
        Ok(GroupListSnapshot { groups })
    }

    pub fn close(&mut self, group_id: &str) -> Result<GroupLeaveResult, PrivateGroupError> {
        let session = self.group_mut(group_id)?;

        if session.joined {
            let own_fp = session.crypto.fingerprint();
            // Everyone leaves the same way: MLS forbids committing your own
            // removal, so a self-Remove proposal goes out and a member who
            // stays commits it. For an ordinary member that is the admin; for
            // the admin it is the successor (`should_commit_departure`).
            let proposal_bytes = session.crypto.leave_proposal_bytes()?;
            let envelope = ControlEnvelope::SelfRemove {
                group_id: session.group_id.clone(),
                from_fingerprint: own_fp.clone(),
                proposal_b64: encode(&proposal_bytes),
            };
            session.publish_control(&envelope)?;
            if session.is_admin {
                // Compatibility only. Clients that predate the tree-derived
                // successor still need to be told who takes over; newer ones
                // ignore this frame and read the commit instead.
                if let Some(next_admin) =
                    successor_of(session.crypto.member_fingerprints(), &own_fp)
                {
                    let handoff = ControlEnvelope::AdminHandoff {
                        group_id: session.group_id.clone(),
                        from_fingerprint: own_fp,
                        next_admin_fingerprint: next_admin,
                    };
                    session.publish_control(&handoff)?;
                }
            }
        }

        // On a shared node dropping the session no longer ends its
        // subscriptions — the node lives on for the other groups, so leaving
        // has to be said out loud or a closed group keeps receiving.
        if let Some(session) = self.groups.remove(group_id) {
            runtime::close_room(
                &self.shared_node,
                &session.node,
                &session.mesh_id,
                &group_channels(group_id),
                &format!("{KIND} {group_id}"),
            );
        }
        self.groups.forget(group_id);
        if let Some(p) = self.groups.persistence() {
            if let Err(error) = p.delete_group(group_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::PERSIST,
                    group_id,
                    &format!("failed to delete persisted group: {error}"),
                );
            }
        }
        Ok(GroupLeaveResult {
            group_id: group_id.to_string(),
            closed: true,
        })
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

impl ConversationSession for GroupSession {
    type Message = GroupMessage;
    type Record = PersistedGroupSession;

    fn conversation_id(&self) -> &str {
        &self.group_id
    }

    fn log(&self) -> &MessageLog<GroupMessage> {
        &self.messages
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.outbound_attempts
    }

    fn record(&self) -> PersistedGroupSession {
        self.to_persisted_record()
    }

    fn write_extra(&self, persistence: &Persistence) {
        // A snapshot write that fails while the record write after it
        // succeeds leaves a row rehydrate can never rebuild. Surface the
        // failure instead of swallowing it.
        if let Err(error) =
            persistence.put_group_mls_snapshot(&self.group_id, &self.crypto.snapshot())
        {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                &self.group_id,
                &format!("MLS snapshot persist failed: {error}"),
            );
        }
    }

    /// Until the MLS group exists the record's group id is an empty
    /// placeholder, and a group saved in that state cannot be rebuilt.
    fn record_is_final(&self) -> bool {
        self.crypto.group_id_bytes().is_some()
    }
}

#[derive(Debug, PartialEq)]
enum SequenceOutcome {
    Done,
    /// A buffered commit exists that cannot be applied yet — the caller
    /// should request a resync.
    Gapped,
}

/// Node-free core of commit sequencing: classify by wire epoch, apply in
/// order, persist applied commits, drain any buffered successors. A commit is
/// confirmed into the dedup set ONLY after a successful apply, so a transient
/// failure or forged blob never poisons future delivery. The outcome always
/// reflects the post-apply gap state, so a still-missing predecessor triggers
/// a resync request regardless of which disposition the current commit took.
fn sequence_commit(
    crypto: &mut MlsSessionCrypto,
    sequencer: &mut CommitSequencer,
    persistence: Option<&Persistence>,
    group_id: &str,
    commit_b64: &str,
) -> Result<SequenceOutcome, PrivateGroupError> {
    let Some(current) = crypto.epoch() else {
        return Ok(SequenceOutcome::Done);
    };
    let commit_bytes = decode(commit_b64)?;
    let wire_epoch = MlsSessionCrypto::commit_epoch(&commit_bytes)?;
    if let Disposition::Apply = sequencer.offer(current, wire_epoch, commit_b64) {
        crypto.process_commit(&commit_bytes)?;
        sequencer.confirm(commit_b64.to_string());
        log_group_commit(persistence, group_id, wire_epoch, &commit_bytes);
        // Buffered successors may be applicable now.
        while let Some(current) = crypto.epoch() {
            let Some(next_b64) = sequencer.drain_ready(current) else {
                break;
            };
            let next_bytes = decode(&next_b64)?;
            crypto.process_commit(&next_bytes)?;
            sequencer.confirm(next_b64);
            log_group_commit(persistence, group_id, current, &next_bytes);
        }
    }
    // AlreadySeen, Buffered, or Apply all end here: report whatever gap
    // remains at the (possibly advanced) current epoch.
    let stuck = crypto.epoch().is_some_and(|current| sequencer.gap(current));
    Ok(if stuck {
        SequenceOutcome::Gapped
    } else {
        SequenceOutcome::Done
    })
}

/// Feed an admin's resync replay through normal sequencing. Returns true when
/// a gap remains after the replay — the admin could not bridge it (fresh
/// state) and the member must rejoin instead of silently desyncing (spec §7).
fn absorb_resync_commits(
    crypto: &mut MlsSessionCrypto,
    sequencer: &mut CommitSequencer,
    persistence: Option<&Persistence>,
    group_id: &str,
    commits: Vec<ResyncCommit>,
) -> bool {
    for commit in commits {
        // Per-commit tolerance: one malformed entry (a forged response can
        // splice one in) must not discard the rest of a genuine replay.
        // Duplicates and stale entries no-op inside the sequencer.
        if let Err(e) =
            sequence_commit(crypto, sequencer, persistence, group_id, &commit.commit_b64)
        {
            dlog::write(
                LogLevel::Warn,
                kinds::RESYNC,
                group_id,
                &format!("bad commit in resync replay: {e}"),
            );
        }
    }
    crypto.epoch().is_some_and(|current| sequencer.gap(current))
}

/// The deterministic successor rule: the lowest member fingerprint, ignoring
/// the departing one. The member that commits an admin's departure and every
/// member that later reads the resulting tree run this same `min()`, so they
/// agree on the new admin without a frame having to carry the answer.
fn successor_of(members: Vec<String>, departing: &str) -> Option<String> {
    members.into_iter().filter(|fp| fp != departing).min()
}

fn log_group_commit(
    persistence: Option<&Persistence>,
    group_id: &str,
    epoch: u64,
    commit_bytes: &[u8],
) {
    if let Some(p) = persistence {
        if let Err(e) = p.append_group_commit(group_id, epoch, commit_bytes) {
            dlog::write(
                LogLevel::Warn,
                kinds::COMMIT,
                group_id,
                &format!("commit log write failed: {e}"),
            );
        }
    }
}

// The session's own machinery, split by concern: publishing, org authority,
// commits, channels, snapshot. All `impl GroupSession` on the same struct.
mod commits;
mod control;
mod data;
mod lifecycle;
mod org_gate;
mod snapshot;
mod wires;

struct ParsedGroupInvite {
    mesh_id: String,
    group_id: String,
    creator_fingerprint: String,
    label: Option<String>,
}

impl ParsedGroupInvite {
    fn parse(raw: &str) -> Result<Self, PrivateGroupError> {
        let url = url::Url::parse(raw)
            .map_err(|error| PrivateGroupError::InvalidInvite(error.to_string()))?;
        if url.scheme() != "mosh" || url.host_str() != Some("group") {
            return Err(PrivateGroupError::InvalidInvite("wrong scheme".to_string()));
        }
        let mesh = query(&url, "mesh")?;
        let group = query(&url, "group")?;
        let fingerprint = url.fragment().unwrap_or_default().replace("fp=", "");
        if fingerprint.is_empty() {
            return Err(PrivateGroupError::InvalidInvite(
                "missing creator fingerprint".to_string(),
            ));
        }
        if fingerprint.len() != INVITE_FINGERPRINT_LEN
            || !fingerprint.chars().all(|c| c.is_ascii_hexdigit())
        {
            return Err(PrivateGroupError::InvalidInvite(
                "fingerprint must be 32 hex chars".to_string(),
            ));
        }
        let fingerprint = fingerprint.to_ascii_uppercase();
        let label = optional_query(&url, "name");
        Ok(Self {
            mesh_id: mesh,
            group_id: group,
            creator_fingerprint: fingerprint,
            label: label.and_then(sanitize_label_str),
        })
    }
}

fn build_invite_uri(
    mesh_id: &str,
    group_id: &str,
    fingerprint: &str,
    label: &Option<String>,
) -> String {
    match label.as_ref().and_then(|value| {
        let encoded = url::form_urlencoded::byte_serialize(value.as_bytes()).collect::<String>();
        if encoded.is_empty() {
            None
        } else {
            Some(encoded)
        }
    }) {
        Some(encoded) => format!(
            "{INVITE_PREFIX}?mesh={mesh_id}&group={group_id}&name={encoded}#fp={fingerprint}"
        ),
        None => format!("{INVITE_PREFIX}?mesh={mesh_id}&group={group_id}#fp={fingerprint}"),
    }
}

fn sanitize_label(raw: Option<String>) -> Result<Option<String>, PrivateGroupError> {
    Ok(raw.and_then(sanitize_label_str))
}

fn sanitize_label_str(raw: String) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let truncated: String = trimmed.chars().take(MAX_LABEL_LEN).collect();
    Some(truncated)
}

fn channel_group_id(channel: &str) -> Option<&str> {
    channel
        .strip_prefix(CONTROL_CHANNEL_PREFIX)
        .or_else(|| channel.strip_prefix(DATA_CHANNEL_PREFIX))
        .or_else(|| channel.strip_prefix(BLOB_CHANNEL_PREFIX))
}

fn group_channels(group_id: &str) -> [String; 3] {
    [
        format!("{CONTROL_CHANNEL_PREFIX}{group_id}"),
        format!("{DATA_CHANNEL_PREFIX}{group_id}"),
        format!("{BLOB_CHANNEL_PREFIX}{group_id}"),
    ]
}

/// Always room-scoped: the shared node's own room is the substrate, so a
/// room-less publish would land where none of this group's peers listen.
///
/// Best-effort: this carries control and blob frames, which report no delivery
/// status of their own, so an empty group is not a failure to hand back. A
/// user message does not come through here — it publishes directly in
/// `publish_prepared`, where "no peers" does fail the send.
fn publish_json<T: Serialize>(
    node: &MossNode,
    mesh_id: &str,
    channel: &str,
    value: &T,
) -> Result<(), PrivateGroupError> {
    let payload =
        serde_json::to_vec(value).map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
    node.publish_room_best_effort(mesh_id, channel, &payload)
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))
}

fn org_context<'a>(
    org_pubkey: Option<&'a str>,
    org_signer: Option<&'a SigningKey>,
) -> Option<(&'a str, &'a SigningKey)> {
    org_pubkey.zip(org_signer)
}

/// Publish on a group control channel: wrapped in the org signed envelope
/// when an org binding is present, raw JSON otherwise (ADR 0007).
fn publish_control_message<T: Serialize>(
    node: &MossNode,
    control_channel: &str,
    mesh_id: &str,
    org: Option<(&str, &SigningKey)>,
    value: &T,
) -> Result<(), PrivateGroupError> {
    match org {
        Some((org_pubkey, signer)) => {
            let payload = serde_json::to_vec(value)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
            let ctx = OrgContext {
                org_pubkey,
                mesh_id,
                channel_kind: control_channel,
            };
            let env = org_envelope::sign(signer, &ctx, &payload);
            publish_json(node, mesh_id, control_channel, &env)
        }
        None => publish_json(node, mesh_id, control_channel, value),
    }
}

/// The node identity key doubles as the org control-channel signer. Its
/// absence is an error, not a downgrade: an org group must never fall back
/// to unauthenticated control traffic.
fn load_org_signer(persistence: Option<&Persistence>) -> Result<SigningKey, PrivateGroupError> {
    let blob = persistence
        .ok_or_else(|| PrivateGroupError::Moss("org group requires persistence".to_string()))?
        .get_moss_identity()
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))?
        .ok_or_else(|| PrivateGroupError::Moss("moss identity unavailable".to_string()))?;
    org_signing::signing_key_from_identity(&blob)
        .map_err(|error| PrivateGroupError::Moss(error.to_string()))
}

fn decode_json<T: for<'de> Deserialize<'de>>(bytes: &[u8]) -> Result<T, PrivateGroupError> {
    serde_json::from_slice(bytes).map_err(|error| PrivateGroupError::Codec(error.to_string()))
}

fn query(url: &url::Url, key: &str) -> Result<String, PrivateGroupError> {
    optional_query(url, key)
        .ok_or_else(|| PrivateGroupError::InvalidInvite(format!("missing {key}")))
}

fn optional_query(url: &url::Url, key: &str) -> Option<String> {
    url.query_pairs()
        .find(|(candidate, _)| candidate == key)
        .map(|(_, value)| value.into_owned())
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
#[cfg(test)]
#[path = "private_group_runtime/runtime_tests.rs"]
mod tests;
