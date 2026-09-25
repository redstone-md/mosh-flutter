mod call_media;
pub(crate) mod contracts;
mod invite;
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

// Minimum gap between MLS handshake control re-publishes. The KeyPackage and
// Welcome exchange is a one-shot publish, but gossip does not buffer for a peer
// that has not meshed yet, so the first publish is routinely lost while
// discovery is still in progress (or the link is flapping). Bob re-sends his
// KeyPackage on this cadence until he processes the Welcome, and each side
// re-sends its Hello on the same cadence until the counterpart answers.
const HANDSHAKE_RESEND_MS: u64 = 2000;

// Cadence for re-announcing our moss peer id to a joined counterpart that does
// not know it. Only fires while `peer_moss_id` is unknown, which after a
// completed handshake means the peer restarted from a record written before it
// had the id -- a state nothing else recovers from, since KeyPackage/Welcome
// (the id's only other carriers) stop once both sides have joined. Slower than
// the handshake cadence: this is a repair path, not a startup path.
const PEER_ANNOUNCE_RESEND_MS: u64 = 5_000;

// How long a Connected session may go without an authenticated frame from the
// counterpart before it admits the counterpart is gone. Two keepalives fit in
// it, so one lost keepalive is not a verdict.
const LOST_WINDOW_MS: u64 = 25_000;

// How long a Connected session stays quiet before it sends a Hello keepalive.
// Any authenticated frame from the counterpart restarts the count, so a busy
// chat sends none; the counterpart answers every Hello outside its own
// HANDSHAKE_RESEND_MS cadence, so one keepalive refreshes both sides.
const KEEPALIVE_MS: u64 = 10_000;

// How long a session keeps its chunks on the room wire after the moss stream
// refused one. Without it every chunk of a batch paid for its own failed
// stream attempt before falling back.
const STREAM_BACKOFF_MS: u64 = 10_000;

// Cadence and cap for automatic re-sends of user messages the peer's runtime
// has not acknowledged yet (DeliveryAck). Moss pubsub has no store-and-forward
// — a frame published into a dead/half-open link is gone — so unacked Sent
// messages re-publish until acked. The cap bounds chatter toward old clients
// that never ack; receivers dedupe by message_id, so re-sends are idempotent.
const AUTO_RESEND_MS: u64 = 15_000;
const AUTO_RESEND_MAX: u32 = 10;

// Cadence and budget for voice-call ring signaling. Moss pubsub drops frames
// published into a flapping link, and a lost CallAccept strands the caller on
// "ringing" against a callee already in an answered call. The caller re-offers
// on this cadence; a callee that has already accepted answers every re-offer
// with a fresh CallAccept, so the re-offer doubles as the accept's ack — the
// same recovery shape as the KeyPackage/Welcome exchange. The ring budget
// outlasts the callee's 30 s auto-decline so a real decline wins the race.
// That callee deadline is `kIncomingNoAnswerTimeout` in
// `lib/src/features/voice_call/incoming_call_modal.dart`; the two are a
// pair and must be changed together.
const CALL_RESEND_MS: u64 = 2_000;
const CALL_RING_TIMEOUT_MS: u64 = 45_000;

// The typing cadence, the expiry window, and the pinned event codes live in
// `conversation::typing` / `conversation::read_events`, shared with the group.
use crate::conversation::typing::{self as typing_shared, TypingGate};

// How many read ids a persisted session record keeps. A DM only ever needs
// "already read?" for recent messages; a cap keeps a long-lived DM's record
// from growing without bound. Receipts older than the cap re-ask once if a
// restored session ever re-renders that far back. Lives in `contracts`
// beside the field it bounds (`contracts::READ_HISTORY_KEEP`).
use crate::conversation::read_events::push_read_event;
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
}

struct PrivateDmSession {
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
        Self::with_transport(
            MossDmTransport::new(shared_node),
            attachment_store,
            persistence,
        )
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

    /// Rebuild sessions + history from the encrypted store. Best-effort: a bad
    /// row is skipped, never fatal.
    pub fn rehydrate(&mut self) {
        let Some(p) = self.sessions.persistence().cloned() else {
            return;
        };
        for rec in self
            .sessions
            .stored_records::<contracts::PersistedSession>()
        {
            let snapshot = match p.get_mls_snapshot(&rec.session_id) {
                Ok(Some(s)) => s,
                Ok(None) => {
                    // A joiner record written before its Welcome carries an
                    // empty group_id and can never rebuild — delete the dead
                    // row instead of warning about it at every startup. A
                    // final record without its snapshot is corruption: its
                    // history rows stay recoverable, so the row is kept.
                    if rec.group_id.is_empty() {
                        let message = match p.delete_session(&rec.session_id) {
                            Ok(()) => "dropping joiner record without MLS snapshot".to_string(),
                            Err(e) => {
                                format!("joiner record without MLS snapshot; delete failed: {e}")
                            }
                        };
                        dlog::write(LogLevel::Info, kinds::REHYDRATE, &rec.session_id, &message);
                    } else {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::REHYDRATE,
                            &rec.session_id,
                            "record without MLS snapshot; row kept",
                        );
                    }
                    continue;
                }
                Err(e) => {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::REHYDRATE,
                        &rec.session_id,
                        &format!("MLS snapshot unreadable: {e}"),
                    );
                    continue;
                }
            };
            let crypto = match MlsSessionCrypto::restore(
                &rec.display_name,
                &rec.signer_public,
                &snapshot,
                &rec.group_id,
            ) {
                Ok(c) => c,
                Err(e) => {
                    dlog::write(
                        LogLevel::Error,
                        kinds::REHYDRATE,
                        &rec.session_id,
                        &format!("crypto restore failed: {e}"),
                    );
                    continue;
                }
            };
            if let Err(e) = self.open_dm_room(
                &rec.mesh_id,
                &rec.session_id,
                rec.listen_port,
                rec.static_peer.clone(),
            ) {
                dlog::write(
                    LogLevel::Error,
                    kinds::REHYDRATE,
                    &rec.session_id,
                    &format!("node start failed: {e}"),
                );
                continue;
            }
            let session = self.restore_session(&rec, crypto);
            // The loaded record already has a valid group_id; don't rewrite it.
            self.sessions.mark_record_final(&rec.session_id);
            self.sessions.insert(rec.session_id.clone(), session);
        }
    }

    /// One session back from its record, with the history replayed into it
    /// and the handshake state read off what came back.
    fn restore_session(
        &mut self,
        rec: &contracts::PersistedSession,
        crypto: MlsSessionCrypto,
    ) -> PrivateDmSession {
        let role = if rec.role_is_alice {
            SessionRole::Alice
        } else {
            SessionRole::Bob
        };
        let mut session = PrivateDmSession::new(
            role,
            rec.display_name.clone(),
            rec.participant_id.clone(),
            rec.session_id.clone(),
            rec.mesh_id.clone(),
            rec.fingerprint.clone(),
            rec.invite_uri.clone(),
            rec.listen_port,
            rec.static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        // Without this the restored session cannot tell whether its
        // counterpart is reachable, and cannot ask the transport to reach it.
        session.peer_moss_id = rec.peer_moss_id.clone();
        // Read state rides the session record: ids the counterpart had
        // authenticated a read of before the restart. Without this a restart
        // would re-ask the counterpart for every receipt it already sent.
        session.peer_read_ids = rec.read_message_ids.clone();
        self.sessions.replay(
            &rec.session_id,
            Restore {
                log: &mut session.messages,
                attempts: &mut session.outbound_attempts,
                transfer: &mut session.transfer,
                local_author: &rec.display_name,
            },
        );
        session.note_restored_history();
        session
    }

    pub fn create_invite(
        &mut self,
        request: StartSessionRequest,
    ) -> Result<InviteCreated, PrivateDmRuntimeError> {
        let persist_listen_port = request.listen_port;
        let persist_static_peer = request.static_peer.clone();
        let mut crypto = MlsSessionCrypto::new(&request.display_name)?;
        crypto.create_group()?;
        let session_id = crypto.random_token("session")?;
        let mesh_id = crypto.random_token("mesh")?;
        let participant_id = crypto.random_token("participant")?;
        let fingerprint = crypto.fingerprint();
        self.open_dm_room(
            &mesh_id,
            &session_id,
            request.listen_port,
            request.static_peer,
        )?;
        // Embed our moss peer id so the joiner can ask the transport to reach
        // us before organic discovery finds us.
        let invite_uri = build_invite_uri(
            &mesh_id,
            &session_id,
            &fingerprint,
            self.transport.local_peer_id().as_deref(),
        );

        let session = PrivateDmSession::new(
            SessionRole::Alice,
            request.display_name,
            participant_id,
            session_id.clone(),
            mesh_id.clone(),
            fingerprint.clone(),
            Some(invite_uri.clone()),
            persist_listen_port,
            persist_static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );

        self.sessions.insert(session_id.clone(), session);

        // Alice's group exists from create_group(), so the record is final the
        // moment it is written.
        self.sessions.persist_record(&session_id, true);

        Ok(InviteCreated {
            invite_uri,
            session_id,
            mesh_id,
            fingerprint,
            listen_address: listen_address(),
        })
    }

    pub fn accept_invite(
        &mut self,
        request: AcceptInviteRequest,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        let invite = ParsedInvite::parse(&request.invite_uri)?;
        if self.sessions.holds(&invite.session_id) {
            return Err(PrivateDmRuntimeError::DuplicateSession(invite.session_id));
        }
        let persist_listen_port = request.listen_port;
        let mut crypto = MlsSessionCrypto::new(&request.display_name)?;
        let participant_id = crypto.random_token("participant")?;
        let key_package = crypto.key_package_bytes()?;
        let persist_static_peer = request.static_peer.clone().or(invite.peer_address.clone());
        self.open_dm_room(
            &invite.mesh_id,
            &invite.session_id,
            request.listen_port,
            persist_static_peer.clone(),
        )?;
        let envelope = ControlEnvelope::KeyPackage {
            session_id: invite.session_id.clone(),
            participant_id: participant_id.clone(),
            from_device: request.display_name.clone(),
            key_package_b64: encode(&key_package),
            moss_peer_id: self.transport.local_peer_id(),
        };
        // Keep the serialized KeyPackage so the drain loop can re-publish it
        // until the Welcome arrives. The first publish below often lands before
        // the mesh link to Alice exists and is silently dropped.
        let key_package_payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;

        let mut session = PrivateDmSession::new(
            SessionRole::Bob,
            request.display_name,
            participant_id,
            invite.session_id.clone(),
            invite.mesh_id,
            invite.fingerprint,
            Some(request.invite_uri),
            persist_listen_port,
            persist_static_peer.clone(),
            Arc::clone(&self.transport),
            crypto,
            Arc::clone(self.sessions.attachment_store()),
        );
        // Pre-seed the creator's moss id from the invite so the transport can
        // be asked to reach it before any frame teaches it; a later
        // KeyPackage/Welcome exchange only confirms the same value. A wrong id
        // costs availability until the handshake corrects it, never identity:
        // the fingerprint still gates MLS.
        session.peer_moss_id = invite.peer_moss_id;
        // One-shot create-time KeyPackage; the handshake pump repeats it.
        session.route_send(ChannelKind::Control, &key_package_payload)?;
        session.pending_key_package = Some(key_package_payload);
        session.last_handshake_send_ms = now_ms();

        let session_id = session.session_id.clone();
        self.sessions.insert(session_id.clone(), session);

        // Deliberately NOT persisted here. Bob has no MLS group until the
        // Welcome, so a record written now would carry an empty group_id and
        // no snapshot — a row rehydrate can never rebuild, warning at every
        // startup. The first tick after the Welcome persists the record and
        // the snapshot together (persist_tail sees the now-final session).

        self.poll_session(&session_id)
    }

    /// Files a text message as `Queued` and lets the outbox drive it out. The
    /// message is on disk before the transport is asked anything, so a restart
    /// keeps it; a transport that refuses right now just leaves it queued.
    pub fn send_message(
        &mut self,
        session_id: &str,
        body: String,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        let message_id = {
            let session = self.session_mut(session_id)?;
            let message = session.messages.stamp(ChatMessage {
                from_device: session.device_id.clone(),
                body,
                message_id: None,
                sent_at_ms: None,
                attachment: None,
                call_event: None,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
                read: None,
            });
            let owned_session_id = session.session_id.clone();
            session
                .outbox()
                .queue(message, owned_session_id)?
                .message_id
        };
        self.sessions.persist_send(session_id, &message_id, true);
        self.deliver_queued(session_id);
        let result = self.send_result(session_id, &message_id)?;
        self.sessions.persist_tail();
        Ok(result)
    }

    /// Signals "I am typing" for one session, driven by the composer's input.
    /// The per-keystroke call is folded down to the refresh cadence inside the
    /// session; a publish the transport refuses is retried on the next call
    /// (no error to the composer — a dropped hint only delays a hint).
    pub fn typing_signal(&mut self, session_id: &str) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        session.publish_typing(now_ms());
        Ok(())
    }

    /// The app-level read-receipts answer, as persisted in the data dir.
    /// Absent file means the default: off.
    pub fn read_receipts_enabled(&self) -> bool {
        crate::read_receipts::load(&crate::api::shared_runtime::resolved_data_dir())
            .is_some_and(|setting| setting.enabled)
    }

    /// Records the app-level read-receipts answer. BOTH values persist: an
    /// off is a decision too, not an absence (the default is off, so only an
    /// explicit on — and an explicit off — must survive a restart).
    pub fn set_read_receipts_enabled(
        &mut self,
        enabled: bool,
    ) -> Result<(), PrivateDmRuntimeError> {
        crate::read_receipts::save(
            &crate::api::shared_runtime::resolved_data_dir(),
            &ReadReceiptsSetting { enabled },
        )
        .map_err(|error| PrivateDmRuntimeError::Moss(error.to_string()))
    }

    /// Reports "the user is looking at this DM": every counterpart message
    /// not yet read gets its ReadReceipt (best-effort, one frame per
    /// message), and each send files the honest `message_read` event. The
    /// api/Dart poll calls this while the conversation screen is open. A
    /// toggle that is off makes this a no-op — no frames, no events — and
    /// by the symmetry rule a user who does not send receipts also ignores
    /// the ones addressed to it.
    pub fn mark_viewed(&mut self, session_id: &str) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        if !self.read_receipts_enabled() {
            return Ok(());
        }
        let session = self.session_mut(session_id)?;
        session.mark_viewed();
        Ok(())
    }

    /// Puts a failed message back in the queue. A message that is already
    /// waiting its turn is left alone and reported as it stands.
    pub fn retry_message(
        &mut self,
        session_id: &str,
        message_id: &str,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        {
            let session = self.session_mut(session_id)?;
            let attempt = session
                .outbound_attempts
                .get(message_id)
                .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
            if matches!(
                attempt.delivery_status,
                MessageDeliveryStatus::Queued | MessageDeliveryStatus::Pending
            ) {
                return self.send_result(session_id, message_id);
            }
            session.outbox().requeue(message_id)?;
        }
        self.sessions.persist_send(session_id, message_id, false);
        self.deliver_queued(session_id);
        self.send_result(session_id, message_id)
    }

    /// Give one session's outbox a turn right now, and write down whatever it
    /// settled.
    fn deliver_queued(&mut self, session_id: &str) {
        let Some(session) = self.sessions.get_mut(session_id) else {
            return;
        };
        for message_id in session.pump_outbox() {
            self.sessions.persist_send(session_id, &message_id, false);
        }
    }

    /// How one message's send stands, as the app is told.
    fn send_result(
        &self,
        session_id: &str,
        message_id: &str,
    ) -> Result<SendMessageResult, PrivateDmRuntimeError> {
        let session = self.session_ref(session_id)?;
        let attempt = session
            .outbound_attempts
            .get(message_id)
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        Ok(SendMessageResult {
            session_id: session.session_id.clone(),
            state: session.state,
            ciphertext_bytes: attempt.ciphertext_bytes,
            message_id: message_id.to_string(),
            sent_at_ms: attempt.sent_at_ms,
            delivery_status: attempt.delivery_status,
            delivery_error: attempt.delivery_error.clone(),
        })
    }

    /// Encrypts a file, stores the sender's own copy, and announces the
    /// manifest to the peer over the MLS-protected control channel.
    pub fn send_attachment(
        &mut self,
        session_id: &str,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        session.send_attachment(file_name, mime, bytes, thumbnail, voice)
    }

    /// Begins (or retries) downloading a peer's attachment.
    pub fn download_attachment(
        &mut self,
        session_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        session.transfer.start_download(attachment_id)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        session_id: &str,
        attachment_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let session = self.session_mut(session_id)?;
        Ok(session.transfer.cancel(attachment_id)?)
    }

    /// Serves a byte range for streaming playback, fetching the region ahead
    /// of the sequential cursor when it has not arrived yet.
    pub fn stream_attachment_range(
        &mut self,
        session_id: &str,
        attachment_id: &str,
        start: u64,
        end: u64,
    ) -> Result<StreamRange, PrivateDmRuntimeError> {
        self.drain_inbound();
        let session = self.session_mut(session_id)?;
        let outcome = session.transfer.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }

    pub fn poll_session(
        &mut self,
        session_id: &str,
    ) -> Result<SessionSnapshot, PrivateDmRuntimeError> {
        self.drain_inbound();
        Ok(self.session_mut(session_id)?.snapshot())
    }

    pub fn list_sessions(&mut self) -> Result<SessionListSnapshot, PrivateDmRuntimeError> {
        self.drain_inbound();
        let mut snapshots: Vec<SessionSnapshot> = self
            .sessions
            .values_mut()
            .map(PrivateDmSession::snapshot)
            .collect();
        snapshots.sort_by(|a, b| a.session_id.cmp(&b.session_id));
        Ok(SessionListSnapshot {
            sessions: snapshots,
        })
    }

    pub fn close_session(
        &mut self,
        session_id: &str,
    ) -> Result<CloseSessionResult, PrivateDmRuntimeError> {
        match self.sessions.remove(session_id) {
            Some(session) => {
                self.transport.close_room(
                    &session.mesh_id,
                    &session_channels(&session.session_id),
                    &format!("{KIND} {session_id}"),
                );
                // Purge persisted state too, otherwise the conversation
                // re-appears on the next launch via rehydrate.
                self.sessions.forget(session_id);
                if let Some(p) = self.sessions.persistence() {
                    if let Err(error) = p.delete_session(session_id) {
                        dlog::write(
                            LogLevel::Warn,
                            kinds::PERSIST,
                            session_id,
                            &format!("failed to delete persisted session: {error}"),
                        );
                    }
                }
                Ok(CloseSessionResult {
                    session_id: session_id.to_string(),
                    closed: true,
                })
            }
            None => Err(PrivateDmRuntimeError::MissingSession),
        }
    }

    /// One protocol step with no caller behind it: take in what arrived and
    /// tick every session. The bridge runs it on its own thread, so
    /// handshakes, keepalives, the outbox and re-sends keep going while the
    /// UI is not polling (a hidden window, a throttled timer).
    pub fn service(&mut self) {
        self.drain_inbound();
    }

    /// Take in every frame that arrived, then give each session its tick.
    /// Called on every runtime entry point and by [`Self::service`].
    fn drain_inbound(&mut self) {
        self.drain_inbound_at(now_ms());
    }

    /// [`Self::drain_inbound`] on a given clock: the frames drained here are
    /// stamped with `now` when the tick records the counterpart's proof.
    fn drain_inbound_at(&mut self, now: u64) {
        for message in self.transport.drain() {
            self.route_frame(message);
        }
        self.tick(now);
    }

    /// Hand one frame to the session it names. Voice-call media never comes
    /// here: it has its own queue (`CallMedia`).
    ///
    /// A single bad inbound frame must never abort the drain — otherwise it
    /// would also fail the caller (e.g. send_message drains first). After a
    /// restart the in-memory replay-dedup set is empty, so the mesh
    /// re-delivers already-consumed MLS messages; decrypting those fails with
    /// "secret deleted to preserve forward secrecy". That is expected, so the
    /// frame is dropped and the drain keeps going.
    fn route_frame(&mut self, message: MossReceivedMessage) {
        if let Some(session_id) = channel_session_id(&message.channel).map(str::to_string) {
            let Some(session) = self.sessions.get_mut(&session_id) else {
                return;
            };
            if let Err(error) = session.handle_moss_message(message) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::FRAME,
                    &session_id,
                    &format!("dropping inbound frame: {error}"),
                );
            }
        }
    }

    /// One heartbeat for every session: reachability, the handshake and hello
    /// repeats, the outbox, the re-sends. Whatever changed an attempt is
    /// written down afterwards, once the mutable borrow is over.
    fn tick(&mut self, now: u64) {
        let lost_window = self.lost_window_ms;
        let mut dirty: Vec<(String, String)> = Vec::new();
        for (session_id, session) in self.sessions.iter_mut() {
            session.pump_attachment_requests();
            session.pump_peer_connect();
            session.pump_liveness(now, lost_window);
            session.pump_handshake(now);
            session.pump_hello(now);
            session.pump_peer_announce(now);
            session.pump_call_signaling(now);
            let changed = session
                .pump_outbox()
                .into_iter()
                .chain(session.pump_unacked_resends(now))
                .chain(session.take_dirty_outbound());
            dirty.extend(changed.map(|message_id| (session_id.clone(), message_id)));
        }
        for (session_id, message_id) in dirty {
            self.sessions.persist_send(&session_id, &message_id, false);
        }
        self.sessions.persist_tail();
        self.sync_call_media();
    }

    /// The call media hub the audio loop sends and drains through.
    pub fn call_media(&self) -> Arc<CallMedia> {
        Arc::clone(&self.media)
    }

    /// Tell the media hub which calls are live. Run after every tick and
    /// every call action: the call state machine lives here, the hub only
    /// mirrors its active calls.
    fn sync_call_media(&self) {
        let live = self
            .sessions
            .values()
            .filter_map(|session| {
                let call = session.call.as_ref()?;
                (call.phase == CallPhase::Active).then(|| LiveCall {
                    call_id: call.call_id.clone(),
                    room: session.mesh_id.clone(),
                    own_direction_bit: call.direction.seq_direction_bit(),
                })
            })
            .collect();
        self.media.sync(live);
        self.media.collect();
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

    pub fn call_start(&mut self, session_id: &str) -> Result<CallStarted, PrivateDmRuntimeError> {
        self.drain_inbound();
        self.session_mut(session_id)?.call_start()
    }

    pub fn call_accept(
        &mut self,
        session_id: &str,
        call_id: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_accept(call_id);
        self.sync_call_media();
        outcome
    }

    pub fn call_decline(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_decline(call_id, reason);
        self.sync_call_media();
        outcome
    }

    pub fn call_end(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        let outcome = self.session_mut(session_id)?.call_end(call_id, reason);
        self.sync_call_media();
        outcome
    }
}

// The session's own machinery, split by channel and concern. Every piece
// below is `impl PrivateDmSession` on the same struct; the split is for
// reading, not for privacy.
mod blob;
mod calls;
mod control;
mod data;
mod session;
mod snapshot;
mod typing;

impl ConversationSession for PrivateDmSession {
    type Message = ChatMessage;
    type Record = contracts::PersistedSession;

    fn conversation_id(&self) -> &str {
        &self.session_id
    }

    fn log(&self) -> &MessageLog<ChatMessage> {
        &self.messages
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.outbound_attempts
    }

    fn record(&self) -> contracts::PersistedSession {
        self.to_persisted_record()
    }

    fn write_extra(&self, persistence: &Persistence) {
        // A snapshot write that fails while the record write after it
        // succeeds leaves a row rehydrate can never rebuild. Surface the
        // failure instead of swallowing it.
        if let Err(error) = persistence.put_mls_snapshot(&self.session_id, &self.crypto.snapshot())
        {
            dlog::write(
                LogLevel::Error,
                kinds::PERSIST,
                &self.session_id,
                &format!("MLS snapshot persist failed: {error}"),
            );
        }
    }

    /// Until the joiner processes the Welcome its record's group id is an
    /// empty placeholder, and a session saved in that state cannot be rebuilt.
    fn record_is_final(&self) -> bool {
        self.crypto.group_id_bytes().is_some()
    }

    fn record_changed(&self) -> bool {
        self.record_dirty
    }

    fn record_written(&mut self) {
        self.record_dirty = false;
    }
}

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
