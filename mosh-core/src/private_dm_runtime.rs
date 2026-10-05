mod admission_authentication;
mod call_media;
pub(crate) mod contracts;
mod devices;
mod invite;
pub(crate) mod invite_ownership;
mod outbox;
pub(crate) mod transport;
mod wire;

use std::collections::HashMap;
use std::sync::Arc;

pub use crate::attachment_runtime::VoiceMeta;
use crate::attachment_runtime::{AttachmentManifest, OutgoingAttachment, StreamRange};
use crate::attachment_store::AttachmentStore;
use crate::conversation::dedup::SeenFrames;
use crate::conversation::history::Restore;
use crate::conversation::message_log::MessageLog;
use crate::conversation::outbound::{OnSent, Outbox};
use crate::conversation::runtime::{ConversationRuntime, ConversationSession};
use crate::conversation::transfer::Transfer;
use crate::conversation::{decode, encode, now_ms};
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::mls_crypto::MlsSessionCrypto;
use crate::outbound_delivery::OutboundAttemptRecord;
use crate::persistence::{Persistence, DM_HISTORY};
use crate::read_receipts::ReadReceiptsSetting;
use crate::voice_call_runtime::{CallPhase, CallState};
pub use call_media::CallMedia;
use call_media::LiveCall;
pub use contracts::{
    AcceptInviteRequest, ActiveCall, AttachmentDescriptor, AttachmentSendResult, AttachmentState,
    AttachmentView, CallEvent, CallOfferBody, CallStarted, ChatMessage, CloseSessionResult,
    ConnectOutcome, DmOffer, DmSessionState, InviteCreated, MeshInfo, MessageDeliveryStatus,
    OutgoingCall, PeerDetail, PendingCall, PrivateDmRuntimeError, ReadReceiptBody,
    SendMessageResult, SessionListSnapshot, SessionSnapshot, SnapshotEvent, StartSessionRequest,
    TypingBody,
};
use invite::{build_invite_uri, listen_address, ParsedInvite};
use transport::PublishError;
pub use transport::{DmTransport, MossDmTransport, PeerTransport};
use wire::{
    blob_channel, channel_session_id, control_channel, data_channel, decode_json,
    voice_call_channel, BlobEnvelope, ChannelKind, ControlEnvelope, DataEnvelope,
};

/// What a DM calls itself in a log line about its room.
const KIND: &str = "dm";

// Retry cached handshake frames until the counterpart joins.
const HANDSHAKE_RESEND_MS: u64 = 2_000;
// Repair pre-peer-id records after restart.
const PEER_ANNOUNCE_RESEND_MS: u64 = 5_000;
// Two missed keepalives establish loss; any authenticated frame resets both.
const LOST_WINDOW_MS: u64 = 25_000;
const KEEPALIVE_MS: u64 = 10_000;
const STREAM_BACKOFF_MS: u64 = 10_000;
// Message-id dedup permits bounded automatic retransmission until DeliveryAck.
const AUTO_RESEND_MS: u64 = 15_000;
const AUTO_RESEND_MAX: u32 = 10;
// Re-offers recover lost accepts. Must outlast Flutter's 30-second auto-decline.
const CALL_RESEND_MS: u64 = 2_000;
const CALL_RING_TIMEOUT_MS: u64 = 45_000;

use crate::conversation::read_events::push_read_event;
use crate::conversation::typing::{self as typing_shared, TypingGate};
use contracts::{prune_read_ids, READ_HISTORY_KEEP};

/// What moved a session's state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionEvent {
    /// The counterpart's KeyPackage or Welcome arrived.
    HandshakeFrame,
    /// A frame that MLS-decrypted, so only the counterpart can have sent it.
    AuthenticatedFrame,
    /// The counterpart stayed out of the transport's reachable set for the
    /// whole lost window.
    CounterpartLost,
}

/// The session state machine. `Connected` is only ever reached on evidence
/// from the other side, and only ever left when that side goes away.
fn next_state(current: DmSessionState, event: SessionEvent) -> DmSessionState {
    match (current, event) {
        (DmSessionState::Pending, SessionEvent::HandshakeFrame) => DmSessionState::Handshaking,
        (_, SessionEvent::AuthenticatedFrame) => DmSessionState::Connected,
        (DmSessionState::Connected, SessionEvent::CounterpartLost) => DmSessionState::Handshaking,
        (other, _) => other,
    }
}

/// The queued messages of one session in the order they were written. The
/// stamp is the order the user typed in; the id breaks a same-millisecond tie
/// the same way on every run.
fn queued_in_order(attempts: &HashMap<String, OutboundAttemptRecord>) -> Vec<String> {
    let mut queued: Vec<(u64, &String)> = attempts
        .iter()
        .filter(|(_, attempt)| attempt.delivery_status == MessageDeliveryStatus::Queued)
        .map(|(id, attempt)| (attempt.sent_at_ms, id))
        .collect();
    queued.sort();
    queued.into_iter().map(|(_, id)| id.clone()).collect()
}

fn random_b64(bytes: usize) -> String {
    use rand::RngCore;
    let mut buf = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut buf);
    base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &buf)
}

use crate::moss_ffi::{MossFfiRuntime, MossReceivedMessage};
use crate::shared_node::SharedMossNode;

pub struct PrivateDmRuntime {
    sessions: ConversationRuntime<PrivateDmSession>,
    /// The one door every DM frame goes through, in and out.
    transport: Arc<dyn DmTransport>,
    /// Voice frames for the live calls; shared with the audio loop, which
    /// never takes this runtime's lock.
    media: Arc<CallMedia>,
    lost_window_ms: u64,
    device_link: Option<devices::DeviceDmLink>,
}

struct PrivateDmSession {
    deletions: crate::message_deletion::DeletionBook,
    history_last_rx_ms: u64,
    recovery_boot_ms: u64,
    /// When the last immediate recovery pull went out; the pump waits a
    /// retry interval before repeating it.
    recovery_pull_ms: u64,
    membership: Option<devices::DeviceMembership>,
    device_signer: Option<ed25519_dalek::SigningKey>,
    device_store: Option<Arc<Persistence>>,
    device_connect_requested: std::collections::HashSet<String>,
    role: SessionRole,
    state: DmSessionState,
    // When the last authenticated frame from the counterpart was drained, on
    // the tick's clock. The lost window and the keepalive count from here.
    last_authenticated_rx_ms: u64,
    // An authenticated frame arrived since the last tick; the tick stamps it.
    authenticated_since_tick: bool,
    // The counterpart's Hello is waiting for our answer.
    hello_answer_due: bool,
    // Until when served chunks skip the moss stream after it refused one.
    stream_backoff_until_ms: u64,
    device_id: String,
    participant_id: String,
    session_id: String,
    mesh_id: String,
    fingerprint: String,
    // Persisted: nothing relearns this after the handshake completes
    // (pump_handshake only resends while !peer_joined), and losing it makes the
    // session unable to tell whether the counterpart is reachable at all.
    peer_moss_id: Option<String>,
    // Set when a persisted field changed after the record was last written, so
    // persist_session_tail rewrites a record it already finalized. peer_moss_id
    // is the only such field: it can arrive, or change on a peer re-handshake,
    // long after the MLS group exists.
    record_dirty: bool,
    last_peer_announce_ms: u64,
    last_hello_send_ms: u64,
    // The peer id last handed to the transport as an explicit connect target.
    // moss retries a registered target on its own, so each id value needs
    // exactly one call; a re-handshake under a fresh id re-registers.
    connect_requested_for: Option<String>,
    // What the last connect request answered, for the diagnostics card.
    last_connect_outcome: Option<ConnectOutcome>,
    // The path to the counterpart the field log last reported.
    logged_reach: PeerTransport,
    invite_uri: Option<String>,
    // Transport coordinates kept so the persisted session record can be
    // rebuilt verbatim (notably to refresh the joiner's group_id after join).
    listen_port: u16,
    static_peer: Option<String>,
    // The remote peer's display name, learned from the first inbound frame.
    peer_display_name: Option<String>,
    // Our side of the MLS handshake is done: Alice added Bob, or Bob joined.
    peer_joined: bool,
    transport: Arc<dyn DmTransport>,
    crypto: MlsSessionCrypto,
    messages: MessageLog<ChatMessage>,
    seen: SeenFrames,
    control_channel: String,
    data_channel: String,
    blob_channel: String,
    transfer: Transfer,
    outbound_attempts: HashMap<String, OutboundAttemptRecord>,
    call: Option<CallState>,
    // MLS handshake retransmit state. Bob keeps his published KeyPackage here
    // and re-sends it (throttled by HANDSHAKE_RESEND_MS) until he joins; Alice
    // caches the Welcome she produced so she can re-answer a repeat KeyPackage
    // without re-running add_members (which would advance the group epoch).
    pending_key_package: Option<Vec<u8>>,
    pending_welcome: Option<Vec<u8>>,
    last_handshake_send_ms: u64,
    // Message ids whose delivery state changed from an INBOUND frame (peer's
    // DeliveryAck); the runtime drains this to persist those rows, since the
    // session itself cannot reach persistence.
    dirty_outbound: Vec<String>,
    // Wall-clock deadline of the peer's typing hint, if one stands. The peer
    // refreshes it inside the window while it keeps typing; silence lets it
    // lapse and its own message clears it at once.
    peer_typing_until_ms: Option<u64>,
    // The send-cadence gate for our own TypingIndicator publishes.
    typing_gate: TypingGate,
    // Message ids of OUR OWN messages the counterpart has authenticated a
    // read of (survives a restart via the session record), plus the ids of
    // the counterpart's messages we have already receipted, so
    // `mark_viewed` sends nothing twice.
    peer_read_ids: Vec<String>,
    sent_read_ids: Vec<String>,
}

#[derive(Clone, Copy)]
enum SessionRole {
    Alice,
    Bob,
}

impl PrivateDmRuntime {
    pub fn from_shared(
        moss: Arc<MossFfiRuntime>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        Self::from_shared_node(SharedMossNode::new(moss), attachment_store, persistence)
    }

    /// The constructor a real client uses: every runtime in the process is
    /// handed the SAME holder, so DMs, channels, groups and orgs all end up on
    /// one node. `from_shared` mints a private holder instead, which is what
    /// tests running two peers over real moss in one process need.
    pub fn from_shared_node(
        shared_node: Arc<SharedMossNode>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        let linked = persistence.is_some();
        let mut runtime = Self::with_transport(
            MossDmTransport::new(shared_node.clone()),
            attachment_store,
            persistence,
        );
        if linked {
            runtime.device_link = Some(devices::DeviceDmLink::new(shared_node));
        }
        runtime
    }

    /// A runtime on any transport. Production passes the moss transport; a
    /// test passes an in-memory one and decides what gets through.
    pub fn with_transport(
        transport: Arc<dyn DmTransport>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        Self {
            sessions: ConversationRuntime::new(attachment_store, persistence, DM_HISTORY),
            media: CallMedia::new(Arc::clone(&transport)),
            transport,
            lost_window_ms: LOST_WINDOW_MS,
            device_link: None,
        }
    }

    /// Put this session's room on the transport, subscribing its three
    /// channels.
    fn open_dm_room(
        &mut self,
        mesh_id: &str,
        session_id: &str,
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.transport
            .open_room(
                mesh_id,
                &session_channels(session_id),
                listen_port,
                static_peer,
            )
            .map_err(PrivateDmRuntimeError::Moss)
    }

    fn session_mut(
        &mut self,
        session_id: &str,
    ) -> Result<&mut PrivateDmSession, PrivateDmRuntimeError> {
        self.sessions
            .get_mut(session_id)
            .ok_or(PrivateDmRuntimeError::MissingSession)
    }

    fn session_ref(&self, session_id: &str) -> Result<&PrivateDmSession, PrivateDmRuntimeError> {
        self.sessions
            .get(session_id)
            .ok_or(PrivateDmRuntimeError::MissingSession)
    }
}

// The session's own machinery, split by channel and concern. Every piece
// below is `impl PrivateDmSession` on the same struct; the split is for
// reading, not for privacy.
mod blob;
mod calls;
mod control;
mod data;
mod deletion;
mod liveness;
mod session;
mod snapshot;
mod typing;

#[cfg(test)]
#[path = "private_dm_runtime/write_coherence_tests.rs"]
mod write_coherence_tests;

impl SessionRole {
    fn as_str(self) -> &'static str {
        match self {
            SessionRole::Alice => "alice",
            SessionRole::Bob => "bob",
        }
    }
}

/// The three channels one DM subscribes to inside its room.
fn session_channels(session_id: &str) -> [String; 3] {
    [
        control_channel(session_id),
        data_channel(session_id),
        blob_channel(session_id),
    ]
}

#[cfg(test)]
#[path = "private_dm_runtime/state_tests.rs"]
mod state_tests;

#[cfg(test)]
#[path = "private_dm_runtime/outbox_tests.rs"]
mod outbox_tests;

#[cfg(test)]
mod durability_tests;

#[cfg(test)]
#[path = "private_dm_runtime/blob_route_tests.rs"]
mod blob_route_tests;

#[cfg(test)]
#[path = "private_dm_runtime/field_log_tests.rs"]
mod field_log_tests;

#[cfg(test)]
#[path = "private_dm_runtime/reachability_tests.rs"]
mod reachability_tests;

#[cfg(test)]
#[path = "private_dm_runtime/call_media_tests.rs"]
mod call_media_tests;

#[cfg(test)]
#[path = "private_dm_runtime/runtime_tests.rs"]
mod tests;

mod actions;
mod lifecycle;
mod pending_join;
mod service;
mod storage;

mod resend;
mod session_transport;
