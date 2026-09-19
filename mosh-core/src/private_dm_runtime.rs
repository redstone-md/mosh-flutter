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
use crate::voice_call_runtime::{CallPhase, CallState};
pub use contracts::{
    AcceptInviteRequest, ActiveCall, AttachmentDescriptor, AttachmentSendResult, AttachmentState,
    AttachmentView, CallEvent, CallOfferBody, CallStarted, ChatMessage, CloseSessionResult,
    ConnectOutcome, DmOffer, DmSessionState, InviteCreated, MeshInfo, MessageDeliveryStatus,
    OutgoingCall, PeerDetail, PendingCall, PrivateDmRuntimeError, SendMessageResult,
    SessionListSnapshot, SessionSnapshot, SnapshotEvent, StartSessionRequest, TypingBody,
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

// How long the counterpart must stay out of the transport's reachable set
// before a Connected session admits it is offline. Bridges momentary
// re-punch gaps without claiming a dead path is live.
const LOST_WINDOW_MS: u64 = 5_000;

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

// Minimum gap between TypingIndicator publishes from one side. The composer
// re-asks on every keystroke; the runtime folds that down to this cadence so
// continued input reads as one steady signal instead of a frame per key.
const TYPING_REFRESH_MS: u64 = 3_000;

// How long a received typing hint stays believable without a refresh. The
// receiver owns the expiry (the sender claims nothing): a refresh inside the
// window renews it, silence lets it lapse, and a real message clears it at
// once — a delivered message contradicts "typing".
const TYPING_EXPIRY_MS: u64 = 5_000;

/// Event code the diagnostics panel renders as "typing" (pinned in
/// `conversation::mesh`). Synthesized into the ring whenever a decrypted
/// hint lands or lapses, so the panel shows typing activity like the node's
/// own reports.
const TYPING_EVENT_CODE: i32 = 10;

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

/// Files one typing event (pinned code 10) into the diagnostics event ring,
/// the same insert `on_moss_event` does for the node's own reports.
fn push_typing_event(session_id: &str, phase: &str) {
    let detail = serde_json::json!({
        "conversation": KIND,
        "session_id": session_id,
        "phase": phase,
    });
    crate::moss_ffi::push_app_event(
        TYPING_EVENT_CODE,
        &detail.to_string(),
    );
}

use crate::moss_ffi::{MossFfiRuntime, MossReceivedMessage};
use crate::shared_node::SharedMossNode;

pub struct PrivateDmRuntime {
    sessions: ConversationRuntime<PrivateDmSession>,
    /// The one door every DM frame goes through, in and out.
    transport: Arc<dyn DmTransport>,
    lost_window_ms: u64,
}

struct PrivateDmSession {
    role: SessionRole,
    state: DmSessionState,
    // When the counterpart dropped out of the transport's reachable set, if
    // it is out now. The lost window is measured from here.
    unreachable_since_ms: Option<u64>,
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
    // When we last published a TypingIndicator, so continued input re-emits
    // no faster than the refresh cadence.
    last_typing_send_ms: u64,
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
                _ => {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::REHYDRATE,
                        &rec.session_id,
                        "missing MLS snapshot",
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

        // Bob has no MLS group until he processes Alice's Welcome, so this
        // record carries an empty group_id placeholder. It is intentionally NOT
        // final here; persist_session_tail refreshes it once the group exists
        // so rehydrate can load it after a restart.
        self.sessions.persist_record(&session_id, false);

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

    /// Take in every frame that arrived, then give each session its tick.
    /// Called on every runtime entry point, so the UI's ~1 s poll is the
    /// heartbeat that drives handshakes, hellos, the outbox and re-sends.
    fn drain_inbound(&mut self) {
        for message in self.transport.drain() {
            self.route_frame(message);
        }
        self.tick(now_ms());
    }

    /// Hand one frame to the session it names, or to every session for a
    /// voice-call channel, which names a call rather than a session.
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
            return;
        }
        if wire::channel_call_id(&message.channel).is_none() {
            return;
        }
        for session in self.sessions.values_mut() {
            if let Err(error) = session.handle_moss_message(message.clone()) {
                dlog::write(LogLevel::Warn, kinds::FRAME, "", &format!("dropping inbound call frame: {error}"));
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
            session.pump_reachability(now, lost_window);
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
        self.session_mut(session_id)?.call_accept(call_id)
    }

    pub fn call_decline(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        self.session_mut(session_id)?.call_decline(call_id, reason)
    }

    pub fn call_end(
        &mut self,
        session_id: &str,
        call_id: &str,
        reason: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.drain_inbound();
        self.session_mut(session_id)?.call_end(call_id, reason)
    }

    pub fn call_send_frame(
        &mut self,
        session_id: &str,
        call_id: &str,
        frame: Vec<u8>,
    ) -> Result<(), PrivateDmRuntimeError> {
        self.session_mut(session_id)?
            .call_send_frame(call_id, frame)
    }

    pub fn call_drain_frames(
        &mut self,
        session_id: &str,
        call_id: &str,
    ) -> Result<Vec<Vec<u8>>, PrivateDmRuntimeError> {
        self.drain_inbound();
        Ok(self.session_mut(session_id)?.call_drain_frames(call_id))
    }
}

impl PrivateDmSession {
    #[allow(clippy::too_many_arguments)]
    fn new(
        role: SessionRole,
        device_id: String,
        participant_id: String,
        session_id: String,
        mesh_id: String,
        fingerprint: String,
        invite_uri: Option<String>,
        listen_port: u16,
        static_peer: Option<String>,
        transport: Arc<dyn DmTransport>,
        crypto: MlsSessionCrypto,
        attachment_store: Arc<AttachmentStore>,
    ) -> Self {
        let control_channel = control_channel(&session_id);
        let data_channel = data_channel(&session_id);
        let blob_channel = blob_channel(&session_id);
        Self {
            role,
            state: DmSessionState::Pending,
            unreachable_since_ms: None,
            device_id,
            participant_id,
            session_id,
            mesh_id,
            fingerprint,
            peer_moss_id: None,
            connect_requested_for: None,
            last_connect_outcome: None,
            invite_uri,
            listen_port,
            static_peer,
            peer_display_name: None,
            peer_joined: false,
            transport,
            crypto,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            control_channel,
            data_channel,
            blob_channel,
            transfer: Transfer::new(attachment_store),
            outbound_attempts: HashMap::new(),
            call: None,
            pending_key_package: None,
            pending_welcome: None,
            last_handshake_send_ms: 0,
            last_peer_announce_ms: 0,
            last_hello_send_ms: 0,
            peer_typing_until_ms: None,
            last_typing_send_ms: 0,
            dirty_outbound: Vec::new(),
            record_dirty: false,
        }
    }

    /// What a replayed history says about the handshake: the peer's display
    /// name comes back from an inbound message, and a session that had joined
    /// starts over as `Handshaking` — nothing from the counterpart has been
    /// seen since the restart, so it is not Connected until it proves itself.
    fn note_restored_history(&mut self) {
        self.peer_display_name = self
            .messages
            .iter()
            .map(|message| message.from_device.as_str())
            .find(|name| !name.is_empty() && *name != self.device_id)
            .map(str::to_string);
        // Bob only ever has a group after the Welcome; Alice has one from the
        // start, so for her only an inbound message proves the handshake ran.
        let handshake_done = self.crypto.is_ready()
            && (matches!(self.role, SessionRole::Bob) || self.peer_display_name.is_some());
        if handshake_done {
            self.peer_joined = true;
            self.state = DmSessionState::Handshaking;
        }
    }

    /// Builds the persisted record from the live session. `group_id` reflects
    /// the current MLS group, so re-persisting after the joiner processes the
    /// Welcome replaces the empty placeholder written at accept time.
    fn to_persisted_record(&self) -> contracts::PersistedSession {
        contracts::PersistedSession {
            role_is_alice: matches!(self.role, SessionRole::Alice),
            display_name: self.device_id.clone(),
            participant_id: self.participant_id.clone(),
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            fingerprint: self.fingerprint.clone(),
            invite_uri: self.invite_uri.clone(),
            signer_public: self.crypto.signer_public(),
            group_id: self.crypto.group_id_bytes().unwrap_or_default(),
            listen_port: self.listen_port,
            static_peer: self.static_peer.clone(),
            peer_moss_id: self.peer_moss_id.clone(),
        }
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    fn outbox(&mut self) -> Outbox<'_, ChatMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    fn handle_moss_message(
        &mut self,
        message: MossReceivedMessage,
    ) -> Result<(), PrivateDmRuntimeError> {
        if self.has_seen_message(&message) {
            return Ok(());
        }
        if message.channel == self.control_channel {
            self.handle_control(message.payload)
        } else if message.channel == self.data_channel {
            self.handle_data(message.payload)
        } else if message.channel == self.blob_channel {
            self.handle_blob(message.payload)
        } else if wire::channel_call_id(&message.channel).is_some() {
            self.handle_voice_call_frame(&message.channel, message.payload)
        } else {
            Ok(())
        }
    }

    fn handle_voice_call_frame(
        &mut self,
        channel: &str,
        payload: Vec<u8>,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call_id) = wire::channel_call_id(channel) else {
            return Ok(());
        };
        if let Some(call) = self.call.as_mut() {
            if call.call_id == call_id {
                call.push_frame(payload);
            }
        }
        Ok(())
    }

    fn has_seen_message(&mut self, message: &MossReceivedMessage) -> bool {
        // Control frames are exempt. The handshake's entire recovery mechanism
        // is re-sending the identical KeyPackage until the peer answers, and
        // this dedup keys on the payload hash — so every retransmission after
        // the first was dropped here, before handle_control ever saw it. The
        // re-answer path written precisely for a lost Welcome was therefore
        // unreachable, and a session whose first Welcome went missing hung on
        // "waiting" forever. Measured on a live pair: 85 KeyPackages published,
        // exactly one delivered, zero re-answers.
        //
        // Safe because every control branch is idempotent — each checks
        // `peer_joined` before acting. Data frames still dedup: those are what
        // would otherwise double up in the message history.
        //
        // Blob frames are exempt for the same reason as control. A receiver
        // that never got chunk 7 asks for chunk 7 again, and that request is
        // byte-identical to the one before it, so the sender dropped every
        // repeat here and never re-served — one lost chunk hung the transfer
        // for good. Users saw exactly that at 63%, 32% and 0%. Re-served chunk
        // frames are byte-identical too, so they need the same exemption.
        // Idempotent on both sides: serve_chunks just re-encrypts, and
        // ingest_chunk answers Duplicate for a chunk already held. What stops
        // the repeats from becoming a flood is the in-flight window in
        // next_chunk_request, not this set.
        if message.channel == self.control_channel || message.channel == self.blob_channel {
            return false;
        }
        self.seen.seen_before(&message.channel, &message.payload)
    }

    /// Remember the peer's display name from an inbound frame's `from_device`.
    fn note_peer_name(&mut self, from_device: &str) {
        if from_device.is_empty() || from_device == self.device_id {
            return;
        }
        if self.peer_display_name.as_deref() != Some(from_device) {
            self.peer_display_name = Some(from_device.to_string());
        }
    }

    /// Remember the peer's moss peer id from the latest frame that carries it.
    /// Latest wins: a peer that restarts without a persisted moss identity
    /// re-handshakes under a fresh peer id, and pinning the first one would
    /// keep asking the transport for a dead id.
    fn note_peer_moss_id(&mut self, id: Option<String>) {
        if let Some(id) = id {
            if self.peer_moss_id.as_deref() != Some(id.as_str()) {
                self.peer_moss_id = Some(id);
                self.record_dirty = true;
            }
        }
    }

    /// The counterpart's handshake frame arrived: the session is no longer
    /// waiting for somebody to show up, and our Hello is due at once.
    fn note_handshake_frame(&mut self) {
        self.peer_joined = true;
        self.state = next_state(self.state, SessionEvent::HandshakeFrame);
        self.last_hello_send_ms = 0;
    }

    /// A frame decrypted, so the counterpart is alive and holds the group.
    /// This is the only way into `Connected`.
    fn note_authenticated_frame(&mut self, from_device: &str) {
        self.note_peer_name(from_device);
        if self.crypto.is_ready() {
            self.peer_joined = true;
            self.state = next_state(self.state, SessionEvent::AuthenticatedFrame);
            self.unreachable_since_ms = None;
            // Session transition the field log carries: the handshake landed
            // and the counterpart is authenticated.
            dlog::write(LogLevel::Info, kinds::HANDSHAKE, &self.session_id, "handshake landed; session connected");
        }
    }

    /// True when a pending KeyPackage should be re-published: the handshake is
    /// not complete, we still hold the payload, and the throttle window elapsed.
    fn handshake_resend_due(&self, now_ms: u64) -> bool {
        !self.peer_joined
            && self.pending_key_package.is_some()
            && now_ms.saturating_sub(self.last_handshake_send_ms) >= HANDSHAKE_RESEND_MS
    }

    /// The single outbound chokepoint for control/data/blob frames. A Data
    /// frame is the user's message and carries a delivery status, so a
    /// refusal has to reach the caller. Control and Blob frames repeat on
    /// their own cadence and report nothing, so "no peers yet" is not news
    /// for them; every other failure still comes back.
    fn route_send(&self, kind: ChannelKind, payload: &[u8]) -> Result<(), PrivateDmRuntimeError> {
        let channel = kind.channel_for(&self.session_id);
        match self.transport.publish(&self.mesh_id, &channel, payload) {
            Ok(()) => Ok(()),
            Err(PublishError::NoPeers(_)) if kind != ChannelKind::Data => Ok(()),
            Err(error) => Err(PrivateDmRuntimeError::Moss(error.to_string())),
        }
    }

    /// Hand the counterpart's moss id to the transport as an explicit connect
    /// target. The substrate is room-blind, so organic discovery only reaches
    /// the counterpart by chance; the explicit target is dialed immediately
    /// and retried by moss's maintenance loop until connected (direct first,
    /// then its own relay). One call per id value: moss keeps the
    /// registration, and a peer that re-handshakes under a fresh identity
    /// re-registers on the id change. Driven by the same ~1s drain tick as
    /// pump_handshake.
    fn pump_peer_connect(&mut self) {
        let Some(id) = self.peer_moss_id.clone() else {
            return;
        };
        if self.connect_requested_for.as_deref() == Some(id.as_str()) {
            return;
        }
        match self.transport.connect_peer(&id) {
            Ok(()) => {
                self.connect_requested_for = Some(id);
                self.last_connect_outcome = Some(ConnectOutcome::Requested);
            }
            // Leave connect_requested_for unset so the next tick retries the
            // registration itself (e.g. node not started yet during rehydrate).
            Err(error) => {
                dlog::write(LogLevel::Error, kinds::CONNECT, &id, &format!("connect_peer failed: {error}"));
                self.last_connect_outcome = Some(ConnectOutcome::Failed);
            }
        }
    }

    /// How the counterpart is reachable right now, or `None` before its id is
    /// known.
    fn reach(&self) -> PeerTransport {
        self.peer_moss_id
            .as_deref()
            .map_or(PeerTransport::None, |id| self.transport.reach(id))
    }

    /// Admit the counterpart is gone once it has been out of reach for the
    /// whole lost window. Without a known id there is nothing to observe, so
    /// nothing is claimed either way.
    fn pump_reachability(&mut self, now_ms: u64, lost_window_ms: u64) {
        if self.peer_moss_id.is_none() {
            return;
        }
        if self.reach() == PeerTransport::None {
            let since = *self.unreachable_since_ms.get_or_insert(now_ms);
            if now_ms.saturating_sub(since) >= lost_window_ms {
                self.state = next_state(self.state, SessionEvent::CounterpartLost);
            }
        } else {
            self.unreachable_since_ms = None;
        }
    }

    /// Best-effort retransmit of the joiner's KeyPackage while the MLS handshake
    /// is still incomplete. Driven by the inbound drain loop (≈1/s), throttled
    /// to HANDSHAKE_RESEND_MS. Once the peer has joined the pending payload is
    /// dropped so nothing is re-sent.
    fn pump_handshake(&mut self, now_ms: u64) {
        if self.peer_joined {
            self.pending_key_package = None;
            return;
        }
        if !self.handshake_resend_due(now_ms) {
            return;
        }
        let Some(payload) = self.pending_key_package.clone() else {
            return;
        };
        self.last_handshake_send_ms = now_ms;
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// Say hello until the counterpart answers with anything authenticated.
    /// Our side of the handshake is done and MLS is ready, so the counterpart
    /// can decrypt this the moment it holds the group; receiving it is its
    /// proof that we are here, and its reply is ours.
    fn pump_hello(&mut self, now_ms: u64) {
        if self.state == DmSessionState::Connected || !self.can_encrypt_for_peer() {
            return;
        }
        if now_ms.saturating_sub(self.last_hello_send_ms) >= HANDSHAKE_RESEND_MS {
            self.send_hello(now_ms);
        }
    }

    /// Our side of the handshake is done and there is a group to encrypt
    /// for.
    fn can_encrypt_for_peer(&self) -> bool {
        self.peer_joined && self.crypto.is_ready()
    }

    /// One Hello: our moss id, MLS-encrypted so only the counterpart can read
    /// it and nobody else can forge it. Loss is fine, the pump repeats it.
    fn send_hello(&mut self, now_ms: u64) {
        let Some(moss_peer_id) = self.transport.local_peer_id() else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(moss_peer_id.as_bytes()) else {
            return;
        };
        let envelope = ControlEnvelope::Hello {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            hello_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        self.last_hello_send_ms = now_ms;
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// Tell a joined counterpart our moss peer id while we do not know theirs.
    /// Symmetric by construction: whichever side is missing the id keeps
    /// announcing, the other side answers with its own announce on receipt, and
    /// both stop as soon as they know.
    fn pump_peer_announce(&mut self, now_ms: u64) {
        if !self.peer_joined || self.peer_moss_id.is_some() {
            return;
        }
        if now_ms.saturating_sub(self.last_peer_announce_ms) < PEER_ANNOUNCE_RESEND_MS {
            return;
        }
        self.last_peer_announce_ms = now_ms;
        if let Err(error) = self.publish_peer_announce() {
            dlog::write(
                LogLevel::Error,
                kinds::ANNOUNCE,
                &self.session_id,
                &format!("peer announce failed: {error}"),
            );
        }
    }

    fn publish_peer_announce(&self) -> Result<(), PrivateDmRuntimeError> {
        let Some(moss_peer_id) = self.transport.local_peer_id() else {
            return Ok(());
        };
        let envelope = ControlEnvelope::PeerAnnounce {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            moss_peer_id,
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)
    }

    /// Whether a queued message can go out now: our side of the handshake is
    /// done, so the ciphertext is at an epoch the counterpart holds, and the
    /// transport reports it reachable.
    fn can_deliver(&self) -> bool {
        self.can_encrypt_for_peer() && self.reach() != PeerTransport::None
    }

    /// Send queued messages oldest first while the counterpart is reachable.
    /// A refusal leaves the message queued and stops the pass, so a newer
    /// message never overtakes an older one. Returns the ids whose attempt
    /// changed so the runtime can persist them.
    fn pump_outbox(&mut self) -> Vec<String> {
        if !self.can_deliver() {
            return Vec::new();
        }
        let mut changed = Vec::new();
        for message_id in queued_in_order(&self.outbound_attempts) {
            if let Err(error) = self.publish_queued(&message_id) {
                dlog::write(
                    LogLevel::Warn,
                    kinds::OUTBOX,
                    &self.session_id,
                    &format!("queued message {message_id} stays queued: {error}"),
                );
                break;
            }
            changed.push(message_id);
        }
        changed
    }

    /// Encrypt one queued message at the current epoch, publish it, and settle
    /// it `Sent`. The bytes are recorded on the attempt so the auto re-sends
    /// replay the same ciphertext the counterpart dedups on.
    fn publish_queued(&mut self, message_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let body = self
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(message_id))
            .map(|message| message.body.clone())
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let sent_at_ms = self
            .outbound_attempts
            .get(message_id)
            .map(|attempt| attempt.sent_at_ms)
            .ok_or_else(|| PrivateDmRuntimeError::MissingMessage(message_id.to_string()))?;
        let ciphertext = self.crypto.encrypt(body.as_bytes())?;
        let envelope = DataEnvelope {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            message_id: Some(message_id.to_string()),
            sent_at_ms: Some(sent_at_ms),
            ciphertext_b64: encode(&ciphertext),
            resend: None,
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Data, &payload)?;
        if let Some(attempt) = self.outbound_attempts.get_mut(message_id) {
            attempt.publish_payload_b64 = encode(&payload);
            attempt.ciphertext_bytes = ciphertext.len();
        }
        self.outbox().settle(message_id, Ok(()), OnSent::Retain)?;
        Ok(())
    }

    /// Re-send user messages the peer has not acknowledged. Moss pubsub has
    /// no store-and-forward, so a frame published into a dead/half-open link
    /// vanishes; unacked Sent attempts re-publish every AUTO_RESEND_MS until
    /// the peer's DeliveryAck lands or AUTO_RESEND_MAX gives up (old client
    /// that never acks — the message keeps its Sent status). Returns the ids
    /// whose attempt state changed so the runtime can persist them.
    fn pump_unacked_resends(&mut self, now_ms: u64) -> Vec<String> {
        if !self.peer_joined {
            return Vec::new();
        }
        let due: Vec<(String, String, u32)> = self
            .outbound_attempts
            .iter()
            .filter(|(_, attempt)| {
                attempt.delivery_status == MessageDeliveryStatus::Sent
                    && attempt.auto_resends < AUTO_RESEND_MAX
                    && now_ms.saturating_sub(attempt.last_send_ms) >= AUTO_RESEND_MS
            })
            .map(|(id, attempt)| {
                (
                    id.clone(),
                    attempt.publish_payload_b64.clone(),
                    attempt.auto_resends,
                )
            })
            .collect();
        let mut changed = Vec::new();
        for (message_id, payload_b64, auto_resends) in due {
            let Ok(payload) = decode(&payload_b64) else {
                continue;
            };
            // Bump the resend counter INSIDE the envelope so the re-sent
            // frame's bytes differ from the original — the receiver's
            // frame-level sha256 dedup would otherwise swallow the duplicate
            // before the re-ack path could run.
            let Ok(mut envelope) = serde_json::from_slice::<DataEnvelope>(&payload) else {
                continue;
            };
            envelope.resend = Some(auto_resends + 1);
            let Ok(bytes) = serde_json::to_vec(&envelope) else {
                continue;
            };
            // Only a re-send the transport took burns a slot — a refusal must
            // not exhaust the budget with zero frames on the wire.
            if self.route_send(ChannelKind::Data, &bytes).is_err() {
                continue;
            }
            if let Some(attempt) = self.outbound_attempts.get_mut(&message_id) {
                attempt.auto_resends += 1;
                attempt.last_send_ms = now_ms;
                // Session transition the field log carries: how many times a
                // message had to be re-sent before the ack arrived.
                dlog::write(
                    LogLevel::Info,
                    kinds::RESEND,
                    &self.session_id,
                    &format!(
                        "resend #{} of message {message_id}",
                        attempt.auto_resends
                    ),
                );
                // At the cap the attempt STAYS: the filter above stops the
                // automatic loop, the message honestly keeps Sent (not
                // Delivered), and a manual retry still has its payload.
            }
            changed.push(message_id);
        }
        changed
    }

    /// Ids whose delivery state changed from inbound frames since the last
    /// drain — the runtime persists these rows.
    fn take_dirty_outbound(&mut self) -> Vec<String> {
        std::mem::take(&mut self.dirty_outbound)
    }

    fn handle_control(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: ControlEnvelope = decode_json(&payload)?;

        match envelope {
            ControlEnvelope::KeyPackage {
                session_id,
                participant_id,
                from_device,
                key_package_b64,
                moss_peer_id,
            } if self.is_alice_session(&session_id, &participant_id) => {
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(moss_peer_id);
                self.answer_key_package(&key_package_b64)
            }
            ControlEnvelope::Welcome {
                session_id,
                participant_id,
                from_device,
                welcome_b64,
                ratchet_tree_b64,
                moss_peer_id,
            } if self.is_bob_session(&session_id, &participant_id) => {
                if self.peer_joined {
                    return Ok(());
                }
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(moss_peer_id);
                self.crypto
                    .join_welcome(&decode(&welcome_b64)?, &decode(&ratchet_tree_b64)?)?;
                self.note_handshake_frame();
                // Joined: stop retransmitting the KeyPackage.
                self.pending_key_package = None;
                Ok(())
            }
            ControlEnvelope::Hello {
                session_id,
                participant_id,
                from_device,
                hello_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts.
                let Ok(plaintext) = self.crypto.decrypt(&decode(&hello_ciphertext_b64)?) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::HANDSHAKE,
                        &session_id,
                        "dropping unverifiable hello",
                    );
                    return Ok(());
                };
                if let Ok(moss_peer_id) = String::from_utf8(plaintext) {
                    self.note_peer_moss_id(Some(moss_peer_id));
                }
                self.note_authenticated_frame(&from_device);
                // Answer so the sender gets its proof too, but not inside
                // our own cadence: two Connected sides would otherwise
                // ping-pong hellos forever.
                let now = now_ms();
                if now.saturating_sub(self.last_hello_send_ms) >= HANDSHAKE_RESEND_MS {
                    self.send_hello(now);
                }
                Ok(())
            }
            ControlEnvelope::DeliveryAck {
                session_id,
                participant_id,
                ack_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts. Forged or garbled acks stop
                // here and the resend loop keeps running.
                let Ok(ciphertext) = decode(&ack_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    dlog::write(
                        LogLevel::Warn,
                        kinds::DELIVERY,
                        &session_id,
                        "dropping unverifiable delivery ack",
                    );
                    return Ok(());
                };
                let Ok(message_id) = String::from_utf8(plaintext) else {
                    return Ok(());
                };
                self.note_authenticated_frame("");
                // The peer's runtime holds the message: settle it as
                // Delivered and stop the auto-resend loop. Unknown ids (ack
                // for an attempt a restart already dropped) are ignored.
                if let Some(attempt) = self.outbound_attempts.remove(&message_id) {
                    self.messages.mark_delivery(
                        &message_id,
                        MessageDeliveryStatus::Delivered,
                        None,
                        attempt.retry_count,
                    )?;
                    self.dirty_outbound.push(message_id.clone());
                    // Session transition the field log carries: the
                    // counterpart's ack settled the message as delivered.
                    dlog::write(
                        LogLevel::Info,
                        kinds::DELIVERY,
                        &self.session_id,
                        &format!("message {message_id} settled delivered"),
                    );
                }
                Ok(())
            }
            ControlEnvelope::TypingIndicator {
                session_id,
                participant_id,
                from_device,
                typing_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                // Decrypting authenticates: only the MLS peer can produce a
                // ciphertext this group accepts, so a forged hint stops here
                // and the session keeps quiet.
                let Ok(ciphertext) = decode(&typing_ciphertext_b64) else {
                    return Ok(());
                };
                let Ok(plaintext) = self.crypto.decrypt(&ciphertext) else {
                    eprintln!("dropping unverifiable typing hint for {session_id}");
                    return Ok(());
                };
                // The body names the device, but the authenticated identity is
                // the envelope's `from_device` + the fact it decrypted; accept
                // the body only when it agrees.
                if let Ok(body) = decode_json::<TypingBody>(&plaintext) {
                    self.note_peer_name(&from_device);
                    if body.device != from_device {
                        return Ok(());
                    }
                }
                self.note_authenticated_frame(&from_device);
                self.note_peer_typing(now_ms());
                Ok(())
            }
            ControlEnvelope::AttachmentManifest {
                session_id,
                participant_id,
                from_device,
                manifest_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                let manifest_json = self.crypto.decrypt(&decode(&manifest_ciphertext_b64)?)?;
                let manifest: AttachmentManifest = decode_json(&manifest_json)?;
                self.note_authenticated_frame(&from_device);
                self.accept_incoming_manifest(from_device, manifest)
            }
            ControlEnvelope::PeerAnnounce {
                session_id,
                participant_id,
                from_device,
                moss_peer_id,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                let was_unknown = self.peer_moss_id.is_none();
                self.note_peer_name(&from_device);
                self.note_peer_moss_id(Some(moss_peer_id));
                // Answer once, and only to an announce that told us something
                // new: the peer announces because IT is missing our id, and
                // without this reply a pair that both restarted would each wait
                // for the other. Answering unconditionally would instead ping-
                // pong forever between two sides that already know each other.
                if was_unknown {
                    let _ = self.publish_peer_announce();
                }
                Ok(())
            }
            other => self.handle_call_control(other),
        }
    }

    /// Alice's side of the handshake. Bob re-sends his KeyPackage until he
    /// sees the Welcome; if we already added him, our first Welcome was
    /// likely lost before his node meshed, so re-answer with the cached copy
    /// rather than calling add_members again (which advances the group
    /// epoch).
    fn answer_key_package(&mut self, key_package_b64: &str) -> Result<(), PrivateDmRuntimeError> {
        if self.peer_joined {
            if let Some(welcome_payload) = self.pending_welcome.clone() {
                return self.route_send(ChannelKind::Control, &welcome_payload);
            }
            return Ok(());
        }
        let key_package = decode(key_package_b64)?;
        let (welcome, tree) = self.crypto.add_peer(&key_package)?;
        self.note_handshake_frame();
        let envelope = ControlEnvelope::Welcome {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            welcome_b64: encode(&welcome),
            ratchet_tree_b64: encode(&tree),
            moss_peer_id: self.transport.local_peer_id(),
        };
        let welcome_payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.pending_welcome = Some(welcome_payload.clone());
        self.route_send(ChannelKind::Control, &welcome_payload)
    }

    /// The Call* control frames. Anything else is an unknown control kind and
    /// is dropped, which is what an older build does with a frame it does not
    /// know.
    fn handle_call_control(
        &mut self,
        envelope: ControlEnvelope,
    ) -> Result<(), PrivateDmRuntimeError> {
        match envelope {
            ControlEnvelope::CallOffer {
                session_id,
                participant_id,
                from_device,
                call_id,
                offer_ciphertext_b64,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                self.handle_call_offer(from_device, call_id, &offer_ciphertext_b64)
            }
            ControlEnvelope::CallAccept {
                session_id,
                participant_id,
                call_id,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if let Some(call) = self.call.as_mut() {
                    if call.call_id == call_id && call.phase == CallPhase::Outgoing {
                        call.become_active(now_ms());
                    }
                }
                Ok(())
            }
            ControlEnvelope::CallDecline {
                session_id,
                participant_id,
                call_id,
                reason: _,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if self.holds_call(&call_id) {
                    self.finish_call("missed", 0);
                }
                Ok(())
            }
            ControlEnvelope::CallEnd {
                session_id,
                participant_id,
                call_id,
                reason: _,
            } if self.is_from_counterpart(&session_id, &participant_id) => {
                if let Some(call) = self.call.as_ref().filter(|call| call.call_id == call_id) {
                    let duration = call.duration_ms(now_ms());
                    let kind = call.end_kind();
                    self.finish_call(kind, duration);
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }

    fn holds_call(&self, call_id: &str) -> bool {
        self.call
            .as_ref()
            .is_some_and(|call| call.call_id == call_id)
    }

    /// An incoming ring. The caller re-offers until it sees our CallAccept,
    /// so a re-offer of the call we already answered means that accept was
    /// dropped: re-send it, or the caller rings out against a callee sitting
    /// in an active call. Any other offer while a call is held is ignored.
    fn handle_call_offer(
        &mut self,
        from_device: String,
        call_id: String,
        offer_ciphertext_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        if let Some(existing) = self.call.as_ref() {
            if existing.call_id == call_id && existing.phase == CallPhase::Active {
                return self.publish_call_accept(&call_id);
            }
            return Ok(());
        }
        let plaintext = self.crypto.decrypt(&decode(offer_ciphertext_b64)?)?;
        let body: CallOfferBody = decode_json(&plaintext)?;
        self.note_authenticated_frame(&from_device);
        let channel = voice_call_channel(&call_id);
        self.call = Some(CallState::ringing(
            call_id,
            body.key_b64,
            body.nonce_prefix_b64,
            from_device,
        ));
        self.transport
            .subscribe(&self.mesh_id, &channel)
            .map_err(PrivateDmRuntimeError::Moss)
    }

    /// Drop the call we hold, leave its channel, and log it in the history.
    fn finish_call(&mut self, kind: &str, duration_ms: u64) {
        let Some(call) = self.call.take() else {
            return;
        };
        let _ = self
            .transport
            .unsubscribe(&self.mesh_id, &voice_call_channel(&call.call_id));
        self.append_call_event_message(&call.remote_device, kind, duration_ms, &call.call_id);
    }

    fn append_call_event_message(
        &mut self,
        remote_device: &str,
        kind: &str,
        duration_ms: u64,
        call_id: &str,
    ) {
        let message = self.messages.stamp(ChatMessage {
            from_device: remote_device.to_string(),
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: None,
            call_event: Some(CallEvent {
                kind: kind.to_string(),
                duration_ms,
                call_id: call_id.to_string(),
            }),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        self.messages.push(message);
    }

    fn handle_data(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: DataEnvelope = decode_json(&payload)?;

        if envelope.session_id != self.session_id || envelope.participant_id == self.participant_id
        {
            return Ok(());
        }

        // Re-ack a message we already hold BEFORE decrypting: MLS forward
        // secrecy makes a second decrypt of the same ciphertext fail, and a
        // duplicate arriving at all usually means our previous ack was lost.
        // This also covers post-restart replays — rehydrated history re-acks
        // instead of erroring on the consumed MLS secret.
        if let Some(message_id) = envelope.message_id.as_deref() {
            if self.has_inbound_message(message_id) {
                self.send_delivery_ack(message_id);
                return Ok(());
            }
        }

        let plaintext = self.crypto.decrypt(&decode(&envelope.ciphertext_b64)?)?;
        self.note_authenticated_frame(&envelope.from_device);
        // A delivered message contradicts "typing": the hint dies at once,
        // whatever its deadline said.
        self.clear_peer_typing();
        let ack_id = envelope.message_id.clone();
        let message = self.messages.stamp(ChatMessage {
            from_device: envelope.from_device,
            body: String::from_utf8_lossy(&plaintext).into_owned(),
            message_id: envelope.message_id,
            sent_at_ms: envelope.sent_at_ms,
            attachment: None,
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        if self.messages.holds_copy_of(&message) {
            return Ok(());
        }
        self.messages.push(message);
        if let Some(message_id) = ack_id.as_deref() {
            self.send_delivery_ack(message_id);
        }

        Ok(())
    }

    /// True when an inbound (peer-authored) message with this id is already
    /// in the log — the trigger for re-acking instead of re-processing.
    fn has_inbound_message(&self, message_id: &str) -> bool {
        self.messages.iter().any(|existing| {
            existing.from_device != self.device_id
                && existing.message_id.as_deref() == Some(message_id)
        })
    }

    /// Best-effort delivery receipt. Loss is fine: the sender keeps
    /// re-sending until a later duplicate provokes a fresh ack. The message
    /// id is MLS-encrypted so only the real peer can mint an ack — plaintext
    /// would let any mesh member fake ✓✓ and silence the resend loop.
    fn send_delivery_ack(&mut self, message_id: &str) {
        let Ok(ciphertext) = self.crypto.encrypt(message_id.as_bytes()) else {
            return;
        };
        let envelope = ControlEnvelope::DeliveryAck {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            ack_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        let _ = self.route_send(ChannelKind::Control, &payload);
    }

    /// Publishes a typing hint if the refresh cadence allows one. The
    /// composer calls this on every keystroke; continued input keeps
    /// refreshing the peer's window at this cadence, and stopping input
    /// simply stops the calls — the peer's own expiry does the rest. No
    /// sender-side expiry state: the receiver owns the deadline.
    fn publish_typing(&mut self, now: u64) {
        if !self.can_encrypt_for_peer() {
            return;
        }
        if now.saturating_sub(self.last_typing_send_ms) < TYPING_REFRESH_MS {
            return;
        }
        let body = TypingBody {
            device: self.device_id.clone(),
            until_ms: now.saturating_add(TYPING_EXPIRY_MS),
        };
        let Ok(body_json) = serde_json::to_vec(&body) else {
            return;
        };
        let Ok(ciphertext) = self.crypto.encrypt(&body_json) else {
            return;
        };
        let envelope = ControlEnvelope::TypingIndicator {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            typing_ciphertext_b64: encode(&ciphertext),
        };
        let Ok(payload) = serde_json::to_vec(&envelope) else {
            return;
        };
        if self.route_send(ChannelKind::Control, &payload).is_err() {
            return;
        }
        self.last_typing_send_ms = now;
    }

    /// A decrypted hint from the counterpart: stamp the deadline from OUR
    /// clock (the sender's `until_ms` stays advisory) and file the event.
    fn note_peer_typing(&mut self, now: u64) {
        let lapsed = self.peer_typing_until_ms.is_none_or(|until| until <= now);
        self.peer_typing_until_ms = Some(now.saturating_add(TYPING_EXPIRY_MS));
        if lapsed {
            push_typing_event(&self.session_id, "started");
        }
    }

    /// Drops the hint once its deadline passes. Driven by the poll/tick
    /// heartbeat, so no timer of its own; files the lapse event once.
    fn expire_peer_typing(&mut self, now: u64) {
        let Some(until) = self.peer_typing_until_ms else {
            return;
        };
        if until > now {
            return;
        }
        self.peer_typing_until_ms = None;
        push_typing_event(&self.session_id, "stopped");
    }

    /// An inbound message contradicts "typing": the hint is cleared at once,
    /// whatever its deadline said.
    fn clear_peer_typing(&mut self) {
        if self.peer_typing_until_ms.take().is_some() {
            push_typing_event(&self.session_id, "stopped");
        }
    }

    fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: BlobEnvelope = decode_json(&payload)?;
        match envelope {
            BlobEnvelope::Request {
                participant_id,
                request,
            } if participant_id != self.participant_id => {
                for frame in self.transfer.serve(&request) {
                    let chunk = BlobEnvelope::Chunk {
                        participant_id: self.participant_id.clone(),
                        frame,
                    };
                    let bytes = serde_json::to_vec(&chunk)
                        .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
                    self.route_send(ChannelKind::Blob, &bytes)?;
                }
                Ok(())
            }
            BlobEnvelope::Chunk {
                participant_id,
                frame,
            } if participant_id != self.participant_id => Ok(self.transfer.ingest(&frame)?),
            _ => Ok(()),
        }
    }

    fn accept_incoming_manifest(
        &mut self,
        from_device: String,
        manifest: AttachmentManifest,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(descriptor) = self.transfer.accept_manifest(manifest)? else {
            return Ok(());
        };
        let message = self.messages.stamp(ChatMessage {
            from_device,
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: Some(descriptor),
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        self.messages.push(message);
        Ok(())
    }

    fn send_attachment(
        &mut self,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateDmRuntimeError> {
        if !self.ready_for_user_actions() {
            return Err(PrivateDmRuntimeError::NotReady);
        }
        let attachment_id = self.crypto.random_token("attachment")?;
        let outgoing = self.transfer.prepare_outgoing(OutgoingAttachment {
            attachment_id: attachment_id.clone(),
            file_name,
            mime,
            from_fingerprint: self.fingerprint.clone(),
            bytes,
            thumbnail_b64: thumbnail,
            voice,
        })?;
        let content_hash = outgoing.manifest.content_hash.clone();
        let manifest_json = serde_json::to_vec(&outgoing.manifest)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        let ciphertext = self.crypto.encrypt(&manifest_json)?;
        let envelope = ControlEnvelope::AttachmentManifest {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            manifest_ciphertext_b64: encode(&ciphertext),
        };
        let payload = serde_json::to_vec(&envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)?;

        let descriptor = self.transfer.record_sent(outgoing);
        let message = self.messages.stamp(ChatMessage {
            from_device: self.device_id.clone(),
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: Some(descriptor),
            call_event: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        self.messages.push(message);
        Ok(AttachmentSendResult {
            conversation_id: self.session_id.clone(),
            attachment_id,
            content_hash,
        })
    }

    fn pump_attachment_requests(&mut self) {
        for request in self.transfer.next_requests() {
            let envelope = BlobEnvelope::Request {
                participant_id: self.participant_id.clone(),
                request,
            };
            if let Ok(bytes) = serde_json::to_vec(&envelope) {
                let _ = self.route_send(ChannelKind::Blob, &bytes);
            }
        }
    }

    /// A frame for this session from the other participant. Our own frames
    /// come back on the shared node and are not news.
    fn is_from_counterpart(&self, session_id: &str, participant_id: &str) -> bool {
        self.session_id == session_id && self.participant_id != participant_id
    }

    fn is_alice_session(&self, session_id: &str, participant_id: &str) -> bool {
        matches!(self.role, SessionRole::Alice)
            && self.session_id == session_id
            && self.participant_id != participant_id
    }

    fn is_bob_session(&self, session_id: &str, participant_id: &str) -> bool {
        matches!(self.role, SessionRole::Bob)
            && self.session_id == session_id
            && self.participant_id != participant_id
    }

    fn snapshot(&mut self) -> SessionSnapshot {
        // The poll is the heartbeat: a hint past its deadline stops being
        // carried (and files its lapse into the event ring) from here.
        self.expire_peer_typing(now_ms());
        SessionSnapshot {
            session_id: self.session_id.clone(),
            mesh_id: self.mesh_id.clone(),
            role: self.role.as_str().to_string(),
            display_name: self.device_id.clone(),
            peer_display_name: self.peer_display_name.clone().unwrap_or_default(),
            state: self.state,
            transport: self.reach(),
            peer_moss_id: self.peer_moss_id.clone(),
            last_connect_outcome: self.last_connect_outcome,
            invite_uri: self.invite_uri.clone(),
            fingerprint: self.fingerprint.clone(),
            messages: self.messages.to_vec(),
            attachments: self.transfer.views(),
            mesh: self.mesh_info(),
            events: crate::conversation::mesh::snapshot_events(),
            pending_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Ringing {
                    Some(PendingCall {
                        call_id: call.call_id.clone(),
                        from_device: call.remote_device.clone(),
                    })
                } else {
                    None
                }
            }),
            outgoing_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Outgoing {
                    Some(OutgoingCall {
                        call_id: call.call_id.clone(),
                    })
                } else {
                    None
                }
            }),
            active_call: self.call.as_ref().and_then(|call| {
                if call.phase == CallPhase::Active {
                    Some(ActiveCall {
                        call_id: call.call_id.clone(),
                        direction: call.direction.as_str().to_string(),
                        key_b64: call.key_b64.clone(),
                        nonce_prefix_b64: call.nonce_prefix_b64.clone(),
                        started_at_ms: call.started_at_ms,
                    })
                } else {
                    None
                }
            }),
            peer_typing_until_ms: self.peer_typing_until_ms,
        }
    }

    fn mesh_info(&self) -> Option<MeshInfo> {
        let mut info = self.transport.mesh_info()?;
        // The node is shared, so it reports every open conversation's channels.
        // This snapshot belongs to ONE of them: showing the others would put
        // another chat's session id in this chat's diagnostics panel. Peer
        // lists stay whole on purpose — `reach` matches the counterpart by id
        // against them.
        info.channels
            .retain(|channel| channel_session_id(channel) == Some(self.session_id.as_str()));
        Some(info)
    }

    /// What needs a live path right now: an attachment, a call. A text never
    /// asks; it queues.
    fn ready_for_user_actions(&self) -> bool {
        self.state == DmSessionState::Connected
    }

    /// Sends one Call* control frame through the transport. Only the media
    /// frames skip the chokepoint's refusal rules (see `call_send_frame`).
    fn send_call_control(&self, envelope: &ControlEnvelope) -> Result<(), PrivateDmRuntimeError> {
        let payload = serde_json::to_vec(envelope)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        self.route_send(ChannelKind::Control, &payload)
    }

    /// Builds and sends a `CallOffer` for a call already in `self.call`. The
    /// body is re-encrypted on every send: MLS deletes the secret behind an
    /// application message once consumed, so a byte-identical replay would fail
    /// to decrypt on the far side instead of re-ringing.
    fn publish_call_offer(
        &mut self,
        call_id: &str,
        key_b64: &str,
        nonce_prefix_b64: &str,
    ) -> Result<(), PrivateDmRuntimeError> {
        let body = CallOfferBody {
            key_b64: key_b64.to_string(),
            nonce_prefix_b64: nonce_prefix_b64.to_string(),
        };
        let body_json = serde_json::to_vec(&body)
            .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
        let ciphertext = self.crypto.encrypt(&body_json)?;
        let envelope = ControlEnvelope::CallOffer {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.device_id.clone(),
            call_id: call_id.to_string(),
            offer_ciphertext_b64: encode(&ciphertext),
        };
        self.send_call_control(&envelope)
    }

    fn publish_call_accept(&self, call_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let envelope = ControlEnvelope::CallAccept {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
        };
        self.send_call_control(&envelope)
    }

    fn call_start(&mut self) -> Result<CallStarted, PrivateDmRuntimeError> {
        if !self.ready_for_user_actions() {
            return Err(PrivateDmRuntimeError::NotReady);
        }
        if self.call.is_some() {
            return Err(PrivateDmRuntimeError::Attachment(
                "another call is already in flight".to_string(),
            ));
        }
        let call_id = self.crypto.random_token("call")?;
        let key_b64 = random_b64(32);
        let nonce_prefix_b64 = random_b64(4);
        self.call = Some(CallState::outgoing(
            call_id.clone(),
            key_b64.clone(),
            nonce_prefix_b64.clone(),
            String::new(),
        ));
        self.transport
            .subscribe(&self.mesh_id, &voice_call_channel(&call_id))
            .map_err(PrivateDmRuntimeError::Moss)?;
        self.publish_call_offer(&call_id, &key_b64, &nonce_prefix_b64)?;
        if let Some(call) = self.call.as_mut() {
            call.mark_offer_sent(now_ms());
        }
        Ok(CallStarted {
            session_id: self.session_id.clone(),
            call_id,
            key_b64,
            nonce_prefix_b64,
        })
    }

    fn call_accept(&mut self, call_id: &str) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_mut() else {
            return Err(PrivateDmRuntimeError::MissingSession);
        };
        if call.call_id != call_id || call.phase != CallPhase::Ringing {
            return Err(PrivateDmRuntimeError::MissingSession);
        }
        call.become_active(now_ms());
        self.publish_call_accept(call_id)
    }

    /// Retransmits the ring while the caller waits, and gives up once the ring
    /// budget is spent. Driven by the same ~1s drain tick as `pump_handshake`.
    fn pump_call_signaling(&mut self, now_ms: u64) {
        let Some(call) = self.call.as_ref() else {
            return;
        };
        if call.phase != CallPhase::Outgoing {
            return;
        }
        let call_id = call.call_id.clone();
        if now_ms.saturating_sub(call.offer_first_ms) >= CALL_RING_TIMEOUT_MS {
            let _ = self.call_end(&call_id, "no_answer");
            return;
        }
        if now_ms.saturating_sub(call.offer_last_ms) < CALL_RESEND_MS {
            return;
        }
        let key_b64 = call.key_b64.clone();
        let nonce_prefix_b64 = call.nonce_prefix_b64.clone();
        match self.publish_call_offer(&call_id, &key_b64, &nonce_prefix_b64) {
            // A failed send must not burn the slot: retry on the next tick.
            Err(error) => dlog::write(
                LogLevel::Error,
                kinds::CALL,
                call_id.as_str(),
                &format!("call offer resend failed: {error}"),
            ),
            Ok(()) => {
                if let Some(call) = self.call.as_mut() {
                    call.mark_offer_sent(now_ms);
                }
            }
        }
    }

    fn call_decline(&mut self, call_id: &str, reason: &str) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref() else {
            return Ok(());
        };
        if call.call_id != call_id {
            return Ok(());
        }
        self.finish_call("missed", 0);
        let envelope = ControlEnvelope::CallDecline {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
            reason: reason.to_string(),
        };
        self.send_call_control(&envelope)
    }

    fn call_end(&mut self, call_id: &str, reason: &str) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref() else {
            return Ok(());
        };
        if call.call_id != call_id {
            return Ok(());
        }
        let duration = call.duration_ms(now_ms());
        let kind = call.end_kind();
        self.finish_call(kind, duration);
        let envelope = ControlEnvelope::CallEnd {
            session_id: self.session_id.clone(),
            participant_id: self.participant_id.clone(),
            call_id: call_id.to_string(),
            reason: reason.to_string(),
        };
        self.send_call_control(&envelope)
    }

    fn call_send_frame(
        &mut self,
        call_id: &str,
        frame: Vec<u8>,
    ) -> Result<(), PrivateDmRuntimeError> {
        let Some(call) = self.call.as_ref() else {
            return Ok(());
        };
        if call.call_id != call_id || call.phase != CallPhase::Active {
            return Ok(());
        }
        // A media frame is never worth a refusal: the next one is 20 ms away.
        match self
            .transport
            .publish(&self.mesh_id, &voice_call_channel(call_id), &frame)
        {
            Ok(()) | Err(PublishError::NoPeers(_)) => Ok(()),
            Err(error) => Err(PrivateDmRuntimeError::Moss(error.to_string())),
        }
    }

    fn call_drain_frames(&mut self, call_id: &str) -> Vec<Vec<u8>> {
        let Some(call) = self.call.as_mut() else {
            return Vec::new();
        };
        if call.call_id != call_id {
            return Vec::new();
        }
        call.drain_frames()
    }
}

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
        let _ = persistence.put_mls_snapshot(&self.session_id, &self.crypto.snapshot());
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
mod tests {
    use super::*;

    use crate::attachment_runtime::CHUNK_SIZE;
    use crate::moss_ffi::{drain_received_messages, MossFfiRuntime, MOSS_TEST_LOCK};

    pub(super) fn temp_store() -> Arc<AttachmentStore> {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "mosh-dm-attachments-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
    }

    // next_path(current, direct_now, direct_stable, direct_gone, elapsed, t_fallback)

    // Real two-node loopback handshake; the gossipsub mesh occasionally fails
    // to form in time, so this is an on-demand smoke test (run with
    // `cargo test -- --ignored`). The persistence/resume logic it exercises is
    // covered deterministically by the crypto restore tests and the
    // handshake-free history_and_session_survive_restart.
    #[test]
    #[ignore]
    fn private_dm_runtime_exchanges_e2ee_message_over_moss() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42130,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42131,
            static_peer: Some("127.0.0.1:42130".to_string()),
        })
        .expect("Bob should accept invite");

        wait_until_ready(&mut alice, &mut bob, &invite.session_id);
        let sent = alice
            .send_message(&invite.session_id, "hello bob".to_string())
            .expect("Alice should send");

        let snapshot = wait_for_message(&mut bob, &invite.session_id, "hello bob");
        assert_eq!(snapshot.state, DmSessionState::Connected);

        // Bob's runtime acks on receipt; Alice's message must reach the
        // Delivered (✓✓) state once she drains the ack.
        let mut delivered = false;
        for _ in 0..40 {
            let _ = bob.poll_session(&invite.session_id);
            let alice_view = alice
                .poll_session(&invite.session_id)
                .expect("poll should pass");
            if alice_view.messages.iter().any(|m| {
                m.message_id.as_deref() == Some(sent.message_id.as_str())
                    && m.delivery_status == Some(MessageDeliveryStatus::Delivered)
            }) {
                delivered = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        assert!(delivered, "Alice's message never reached Delivered");
    }

    #[test]
    fn waiting_creator_invite_survives_restart() {
        use crate::persistence::Persistence;
        use std::path::PathBuf;

        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!(
            "mosh-dm-waiting-invite-{}.redb",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [29u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        let (session_id, invite_uri) = {
            let mut alice = PrivateDmRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            let invite = alice
                .create_invite(StartSessionRequest {
                    display_name: "Alice".to_string(),
                    listen_port: 42170,
                    static_peer: None,
                })
                .expect("Alice invite should be created");
            (invite.session_id, invite.invite_uri)
        };

        let mut revived =
            PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
        revived.rehydrate();

        let listing = revived.list_sessions().expect("listing should pass");
        let session = listing
            .sessions
            .iter()
            .find(|session| session.session_id == session_id)
            .expect("waiting invite should rehydrate");

        assert_eq!(session.state, DmSessionState::Pending);
        assert_eq!(session.role, "alice");
        assert_eq!(session.invite_uri.as_deref(), Some(invite_uri.as_str()));
        assert!(session.messages.is_empty());

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn restored_inbound_history_waits_for_live_peer() {
        use crate::persistence::Persistence;
        use std::path::PathBuf;

        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!("mosh-dm-inbound-ready-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [31u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        let session_id = {
            let mut alice = PrivateDmRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            let invite = alice
                .create_invite(StartSessionRequest {
                    display_name: "Alice".to_string(),
                    listen_port: 42171,
                    static_peer: None,
                })
                .expect("Alice invite should be created");
            let message_id = "inbound-000001";
            let sent_at_ms = 1;
            let message = ChatMessage {
                from_device: "Bob".to_string(),
                body: "hello from bob".to_string(),
                message_id: Some(message_id.to_string()),
                sent_at_ms: Some(sent_at_ms),
                attachment: None,
                call_event: None,
                delivery_status: None,
                delivery_error: None,
                retryable: None,
                retry_count: None,
            };
            let record = crate::conversation::history::StoredMessage {
                conversation_id: invite.session_id.clone(),
                sent_at_ms,
                message_id: message_id.to_string(),
                message,
            };
            persistence
                .append_message(
                    &invite.session_id,
                    sent_at_ms,
                    message_id,
                    &serde_json::to_vec(&record).expect("record should serialize"),
                )
                .expect("inbound message should persist");
            invite.session_id
        };

        let mut revived =
            PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
        revived.rehydrate();

        let listing = revived.list_sessions().expect("listing should pass");
        let session = listing
            .sessions
            .iter()
            .find(|session| session.session_id == session_id)
            .expect("session should rehydrate");

        assert_eq!(session.peer_display_name, "Bob");
        // The peer was here once, but nothing proves it is now.
        assert_eq!(session.state, DmSessionState::Handshaking);
        assert_eq!(session.messages.len(), 1);

        let _ = std::fs::remove_file(&db_path);
    }

    // The invite embeds the creator's moss peer id and accept_invite must copy
    // it onto the session, or a hard-NAT joiner cannot relay the handshake
    // before the first direct window teaches it the id.
    #[test]
    fn accept_invite_preseeds_peer_moss_id_from_the_invite() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42190,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        assert!(
            invite.invite_uri.contains("&moss="),
            "invite must carry the creator moss id: {}",
            invite.invite_uri
        );

        let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42191,
            static_peer: Some("127.0.0.1:42190".to_string()),
        })
        .expect("Bob should accept invite");

        let alice_id = alice
            .sessions
            .get(&invite.session_id)
            .expect("Alice session should exist")
            .transport
            .local_peer_id()
            .expect("Alice node should expose its key");
        let bob_session = bob
            .sessions
            .get(&invite.session_id)
            .expect("Bob session should exist");
        assert_eq!(bob_session.peer_moss_id.as_deref(), Some(alice_id.as_str()));
    }

    // On the room-blind shared substrate two DM endpoints only ever connect by
    // chance, so each session must hand its counterpart's moss id to moss as an
    // explicit connect target the moment the id is known: Bob from the invite,
    // Alice from the first handshake frame; a re-handshake under a fresh id
    // must re-register.
    #[test]
    fn sessions_request_explicit_connect_to_counterpart() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42172,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42173,
            static_peer: Some("127.0.0.1:42172".to_string()),
        })
        .expect("Bob should accept invite");

        // Bob's id was preseeded from the invite, so the accept-time drain tick
        // must already have registered the explicit target.
        let bob_session = bob
            .sessions
            .get(&invite.session_id)
            .expect("Bob session should exist");
        assert_eq!(
            bob_session.connect_requested_for, bob_session.peer_moss_id,
            "Bob requests an explicit connect to the invite's moss id"
        );
        assert!(bob_session.connect_requested_for.is_some());

        // Alice has not learned Bob's id yet: nothing to request.
        let alice_session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        assert_eq!(alice_session.connect_requested_for, None);

        // Alice learns the id -> the next pump registers it.
        let bob_id = "cd".repeat(32);
        alice_session.peer_moss_id = Some(bob_id.clone());
        alice_session.pump_peer_connect();
        assert_eq!(
            alice_session.connect_requested_for.as_deref(),
            Some(bob_id.as_str())
        );

        // Peer re-handshakes under a fresh moss identity -> re-register.
        let fresh_id = "ef".repeat(32);
        alice_session.peer_moss_id = Some(fresh_id.clone());
        alice_session.pump_peer_connect();
        assert_eq!(
            alice_session.connect_requested_for.as_deref(),
            Some(fresh_id.as_str())
        );
    }

    // D2 regression: the KeyPackage->Welcome handshake is a one-shot publish.
    // If it lands before the mesh link forms it is lost, and nothing used to
    // re-send it, so the session hung on "waiting" forever even after the peer
    // joined the transport. Bob must keep the KeyPackage and re-send it until
    // he joins.
    #[test]
    fn bob_retransmits_key_package_until_joined() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42180,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42181,
            static_peer: Some("127.0.0.1:42180".to_string()),
        })
        .expect("Bob should accept invite");

        let session = bob
            .sessions
            .get_mut(&invite.session_id)
            .expect("Bob session should exist");
        assert!(
            session.pending_key_package.is_some(),
            "Bob retains the KeyPackage for retransmit"
        );
        assert!(!session.peer_joined);

        // Throttle from a known baseline (accept_invite stamped real-now).
        session.last_handshake_send_ms = 0;
        assert!(
            session.handshake_resend_due(HANDSHAKE_RESEND_MS + 1),
            "resend is due once the throttle window elapses"
        );
        assert!(
            !session.handshake_resend_due(HANDSHAKE_RESEND_MS - 1),
            "resend is suppressed inside the throttle window"
        );

        // Welcome processed -> handshake complete -> stop retransmitting.
        session.peer_joined = true;
        session.pump_handshake(HANDSHAKE_RESEND_MS * 10);
        assert!(
            session.pending_key_package.is_none(),
            "joining clears the pending KeyPackage"
        );
        assert!(!session.handshake_resend_due(HANDSHAKE_RESEND_MS * 100));
    }

    // D2 regression: Alice's Welcome can also be lost before Bob meshes. Since
    // add_members cannot run twice (it would advance the group epoch), Alice
    // must cache the Welcome and re-answer Bob's repeated KeyPackage with it.
    #[test]
    fn alice_caches_welcome_and_reanswers_repeat_key_package() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42182,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
        let key_package_b64 = encode(
            &bob_crypto
                .key_package_bytes()
                .expect("Bob key package should build"),
        );
        let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
            session_id: invite.session_id.clone(),
            participant_id: "bob-participant".to_string(),
            from_device: "Bob".to_string(),
            key_package_b64,
            moss_peer_id: None,
        })
        .expect("KeyPackage envelope should serialize");

        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");

        session
            .handle_control(payload.clone())
            .expect("first KeyPackage should add Bob");
        assert!(session.peer_joined);
        assert!(
            session.pending_welcome.is_some(),
            "Alice caches the Welcome she produced"
        );
        assert_eq!(session.crypto.member_count(), 2);

        // Bob's retransmit must be re-answered, never trigger a second add.
        session
            .handle_control(payload)
            .expect("repeat KeyPackage should re-answer with the cached Welcome");
        assert_eq!(
            session.crypto.member_count(),
            2,
            "repeat KeyPackage must not re-run add_members"
        );
        assert!(session.pending_welcome.is_some());
    }

    // The dedup above handle_control is what made every D2 retransmit fix
    // ineffective in the field. Bob re-sends the *identical* KeyPackage bytes,
    // so a payload-hash dedup drops every copy after the first and the
    // re-answer path never runs — a session whose first Welcome was lost hung
    // on "waiting" forever. The existing handshake tests call handle_control
    // directly and so never crossed this layer.
    #[test]
    fn repeat_control_frames_reach_the_handler_while_data_still_dedups() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42184,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");

        let bytes = b"identical retransmission".to_vec();
        let control = MossReceivedMessage {
            channel: session.control_channel.clone(),
            payload: bytes.clone(),
        };
        let data = MossReceivedMessage {
            channel: session.data_channel.clone(),
            payload: bytes,
        };

        assert!(!session.has_seen_message(&control));
        assert!(
            !session.has_seen_message(&control),
            "an identical control frame must still reach handle_control — \
             re-sending it unchanged is how the handshake recovers"
        );

        // Data frames keep deduping, or a resent message doubles in history.
        assert!(!session.has_seen_message(&data));
        assert!(
            session.has_seen_message(&data),
            "a repeated data frame must be suppressed"
        );
    }

    // The same dedup, one channel over. A receiver missing chunk 7 asks for
    // chunk 7 again, and that request is byte-identical to the last one, so
    // every repeat was dropped before handle_blob and the sender never
    // re-served — the transfer hung at 63% for good. Driven through
    // handle_moss_message on purpose: the attachment tests call the handlers
    // directly and so never cross the layer the bug lives in.
    #[test]
    fn a_repeated_chunk_request_still_reaches_the_sender() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42186,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");

        session
            .transfer
            .prepare_outgoing(OutgoingAttachment {
                attachment_id: "att-1".to_string(),
                file_name: "photo.bin".to_string(),
                mime: "application/octet-stream".to_string(),
                from_fingerprint: session.fingerprint.clone(),
                bytes: vec![7u8; 512],
                thumbnail_b64: None,
                voice: None,
            })
            .expect("outgoing attachment should register");

        let payload = serde_json::to_vec(&BlobEnvelope::Request {
            participant_id: "peer-participant".to_string(),
            request: crate::attachment_runtime::ChunkRequest {
                attachment_id: "att-1".to_string(),
                chunk_indices: vec![0],
            },
        })
        .expect("blob request should serialize");
        let request = MossReceivedMessage {
            channel: session.blob_channel.clone(),
            payload,
        };

        session
            .handle_moss_message(request.clone())
            .expect("first chunk request should be served");
        session
            .handle_moss_message(request)
            .expect("repeat chunk request should be served again");
        assert_eq!(
            session.transfer.served_count("att-1", 0),
            2,
            "an identical re-request must reach handle_blob — re-asking \
             unchanged is how a lost chunk is recovered"
        );
    }

    // Task 3: the moss peer-id rides along in the KeyPackage so Alice can
    // learn Bob's relay address without a separate exchange.
    #[test]
    fn handle_control_captures_peer_moss_id_from_key_package() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42183,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
        let key_package_b64 = encode(
            &bob_crypto
                .key_package_bytes()
                .expect("Bob key package should build"),
        );
        let bob_moss_peer_id = "ab".repeat(32);
        let payload = serde_json::to_vec(&ControlEnvelope::KeyPackage {
            session_id: invite.session_id.clone(),
            participant_id: "bob-participant".to_string(),
            from_device: "Bob".to_string(),
            key_package_b64,
            moss_peer_id: Some(bob_moss_peer_id.clone()),
        })
        .expect("KeyPackage envelope should serialize");

        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");

        session
            .handle_control(payload)
            .expect("KeyPackage should add Bob");
        assert_eq!(session.peer_moss_id, Some(bob_moss_peer_id));
    }

    // A peer that restarts without a persisted moss identity re-handshakes
    // under a fresh peer-id; the latest KeyPackage must replace the stale pin
    // or every relayed send keeps targeting a dead id.
    #[test]
    fn key_package_with_new_moss_id_replaces_stale_pin() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42187,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob_crypto = MlsSessionCrypto::new("Bob").expect("Bob crypto should init");
        let key_package_b64 = encode(
            &bob_crypto
                .key_package_bytes()
                .expect("Bob key package should build"),
        );
        let make_payload = |moss_peer_id: String| {
            serde_json::to_vec(&ControlEnvelope::KeyPackage {
                session_id: invite.session_id.clone(),
                participant_id: "bob-participant".to_string(),
                from_device: "Bob".to_string(),
                key_package_b64: key_package_b64.clone(),
                moss_peer_id: Some(moss_peer_id),
            })
            .expect("KeyPackage envelope should serialize")
        };

        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        session
            .handle_control(make_payload("ab".repeat(32)))
            .expect("first KeyPackage should add Bob");
        assert_eq!(session.peer_moss_id, Some("ab".repeat(32)));

        session
            .handle_control(make_payload("cd".repeat(32)))
            .expect("resent KeyPackage should be handled");
        assert_eq!(
            session.peer_moss_id,
            Some("cd".repeat(32)),
            "restarted peer's fresh moss id should replace the stale pin"
        );
    }

    // Builds a lone Alice session on `port` — enough to drive the session-level
    // pumps and control handlers without a live counterpart.
    fn lone_session(port: u16) -> (PrivateDmRuntime, String) {
        drain_received_messages();
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: port,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        (alice, invite.session_id)
    }

    fn test_call_offer_json(session_id: &str, call_id: &str) -> Vec<u8> {
        serde_json::to_vec(&ControlEnvelope::CallOffer {
            session_id: session_id.to_string(),
            participant_id: "the-other-participant".to_string(),
            from_device: "Bob".to_string(),
            call_id: call_id.to_string(),
            // The already-answered branch returns before decrypting.
            offer_ciphertext_b64: "Y2lwaGVy".to_string(),
        })
        .expect("offer should serialize")
    }

    // Call regression: CallOffer was a one-shot publish, so a ring lost on a
    // flapping link never repeated and the caller waited forever. The offer must
    // repeat on the CALL_RESEND_MS cadence while the call is unanswered.
    #[test]
    fn caller_retransmits_the_call_offer_while_unanswered() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let (mut alice, session_id) = lone_session(42197);
        let session = alice
            .sessions
            .get_mut(&session_id)
            .expect("Alice session should exist");

        let mut call = CallState::outgoing("call-1".into(), "k".into(), "n".into(), String::new());
        call.mark_offer_sent(1_000);
        session.call = Some(call);

        session.pump_call_signaling(1_000 + CALL_RESEND_MS - 1);
        assert_eq!(
            session.call.as_ref().expect("call held").offer_last_ms,
            1_000,
            "a resend inside the throttle window is suppressed"
        );

        let due = 1_000 + CALL_RESEND_MS;
        session.pump_call_signaling(due);
        assert_eq!(
            session.call.as_ref().expect("call held").offer_last_ms,
            due,
            "the offer re-publishes once the cadence is due"
        );

        // Answered: the ring stops repeating.
        session
            .call
            .as_mut()
            .expect("call held")
            .become_active(due + 1);
        session.pump_call_signaling(due + CALL_RESEND_MS * 10);
        assert_eq!(
            session.call.as_ref().expect("call held").offer_last_ms,
            due,
            "an answered call stops re-offering"
        );
    }

    // The ring budget is measured from the FIRST offer, so retransmits cannot
    // extend it indefinitely. Timing out logs the call as missed and clears it,
    // which is what closes the caller's outgoing modal.
    #[test]
    fn caller_gives_up_once_the_ring_budget_is_spent() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let (mut alice, session_id) = lone_session(42198);
        let session = alice
            .sessions
            .get_mut(&session_id)
            .expect("Alice session should exist");

        let mut call = CallState::outgoing("call-2".into(), "k".into(), "n".into(), String::new());
        call.mark_offer_sent(1_000);
        call.mark_offer_sent(1_000 + CALL_RING_TIMEOUT_MS - 1);
        session.call = Some(call);

        session.pump_call_signaling(1_000 + CALL_RING_TIMEOUT_MS);
        assert!(
            session.call.is_none(),
            "the unanswered call is cleared once the budget is spent"
        );
        let logged = session
            .messages
            .iter()
            .filter_map(|message| message.call_event.as_ref())
            .find(|event| event.call_id == "call-2")
            .expect("the timed-out call is logged");
        assert_eq!(logged.kind, "missed");
    }

    // The heart of the bug: the callee answered, its CallAccept was dropped, and
    // nothing ever re-sent it — the caller rang out against a peer already in an
    // active call. A repeated offer for a call we hold as Active must re-answer.
    #[test]
    fn answered_callee_re_accepts_a_repeated_offer() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let (mut alice, session_id) = lone_session(42199);
        let session = alice
            .sessions
            .get_mut(&session_id)
            .expect("Alice session should exist");

        let mut call = CallState::ringing("call-3".into(), "k".into(), "n".into(), "Bob".into());
        call.become_active(1_000);
        session.call = Some(call);

        // Fail the next publish, so the error IS the observation that a
        // CallAccept went out.
        let _publish_fail = wire::fail_next_test_publish("observe the accept");
        let offer = test_call_offer_json(&session_id, "call-3");
        assert!(
            session.handle_control(offer.clone()).is_err(),
            "a repeated offer for an answered call re-sends the CallAccept"
        );
        assert_eq!(
            session.call.as_ref().expect("call held").phase,
            CallPhase::Active,
            "the repeat does not disturb the answered call"
        );

        // Still ringing (user has not picked up): nothing to re-answer yet.
        session.call.as_mut().expect("call held").phase = CallPhase::Ringing;
        assert!(
            session.handle_control(offer).is_ok(),
            "an unanswered ring must not auto-accept on the repeat"
        );
    }

    // The peer's DeliveryAck upgrades Sent → Delivered and retires the
    // attempt (stopping the auto-resend loop).
    #[test]
    fn forged_delivery_ack_does_not_upgrade() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42194,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        // No peer is known yet, so the text waits in the queue.
        let result = alice
            .send_message(&invite.session_id, "ping".to_string())
            .expect("send should queue");
        assert_eq!(result.delivery_status, MessageDeliveryStatus::Queued);

        // Forgery #1: garbage ciphertext — an attacker without the MLS group
        // secrets cannot produce anything that decrypts.
        let forged = serde_json::to_vec(&ControlEnvelope::DeliveryAck {
            session_id: invite.session_id.clone(),
            participant_id: "peer-participant".to_string(),
            ack_ciphertext_b64: encode(b"not-an-mls-ciphertext"),
        })
        .expect("ack should serialize");
        // Forgery #2: a REPLAYED ciphertext minted by this very group member
        // (MLS cannot decrypt own messages, so even this is rejected).
        let self_minted = {
            let session = alice
                .sessions
                .get_mut(&invite.session_id)
                .expect("Alice session should exist");
            let ciphertext = session
                .crypto
                .encrypt(result.message_id.as_bytes())
                .expect("encrypt should work");
            serde_json::to_vec(&ControlEnvelope::DeliveryAck {
                session_id: invite.session_id.clone(),
                participant_id: "peer-participant".to_string(),
                ack_ciphertext_b64: encode(&ciphertext),
            })
            .expect("ack should serialize")
        };

        let session = alice
            .sessions
            .get_mut(&invite.session_id)
            .expect("Alice session should exist");
        session
            .handle_control(forged)
            .expect("forged ack must not error");
        session
            .handle_control(self_minted)
            .expect("replayed ack must not error");

        let session = &alice.sessions[&invite.session_id];
        assert!(
            session.outbound_attempts.contains_key(&result.message_id),
            "attempt must survive forged acks"
        );
        let message = session
            .messages
            .iter()
            .find(|m| m.message_id.as_deref() == Some(result.message_id.as_str()))
            .expect("message exists");
        assert_eq!(
            message.delivery_status,
            Some(MessageDeliveryStatus::Queued),
            "no forged Delivered"
        );
    }

    #[test]
    fn history_and_session_survive_restart() {
        use crate::persistence::Persistence;
        use std::path::PathBuf;

        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!("mosh-dm-rehydrate-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [9u8; 32]).expect("store should open"));

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        // Runtime #1: create an invite + send one message, then drop it.
        let session_id = {
            let mut alice = PrivateDmRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            let invite = alice
                .create_invite(StartSessionRequest {
                    display_name: "Alice".to_string(),
                    listen_port: 42140,
                    static_peer: None,
                })
                .expect("Alice invite should be created");
            alice
                .send_message(&invite.session_id, "hello after restart".to_string())
                .expect("Alice should send");
            invite.session_id
        };

        // Runtime #2: rehydrate from the SAME store and prove the message is back.
        let mut revived = PrivateDmRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        revived.rehydrate();

        let listing = revived.list_sessions().expect("listing should pass");
        let session = listing
            .sessions
            .iter()
            .find(|s| s.session_id == session_id)
            .expect("rehydrated session should be present");

        let matching: Vec<&ChatMessage> = session
            .messages
            .iter()
            .filter(|m| m.body == "hello after restart")
            .collect();
        assert_eq!(
            matching.len(),
            1,
            "expected exactly one rehydrated message, dup-guard failed: {:?}",
            session.messages
        );

        // Dup-guard: re-listing (which drains inbound + persists tail) must not
        // duplicate the loaded message.
        let listing2 = revived.list_sessions().expect("second listing should pass");
        let session2 = listing2
            .sessions
            .iter()
            .find(|s| s.session_id == session_id)
            .expect("session should still be present");
        let matching2 = session2
            .messages
            .iter()
            .filter(|m| m.body == "hello after restart")
            .count();
        assert_eq!(
            matching2, 1,
            "tail-persist re-append duplicated the message"
        );

        let _ = std::fs::remove_file(&db_path);
    }

    // Sessions restored from a record written before peer_moss_id was persisted
    // carry None and nothing else recovers it, so the peer must be able to
    // re-announce out of band. Repairs history rather than requiring a new DM.
    #[test]
    fn a_peer_announce_restores_a_lost_peer_id() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let (mut alice, session_id) = lone_session(42163);
        let session = alice
            .sessions
            .get_mut(&session_id)
            .expect("Alice session should exist");

        // The shape a pre-fix record rehydrates into: joined, but peerless.
        session.peer_joined = true;
        session.peer_moss_id = None;
        session.record_dirty = false;

        let peer_id = "ab".repeat(32);
        let announce = serde_json::to_vec(&ControlEnvelope::PeerAnnounce {
            session_id: session_id.clone(),
            participant_id: "the-other-participant".to_string(),
            from_device: "Bob".to_string(),
            moss_peer_id: peer_id.clone(),
        })
        .expect("announce should serialize");

        session
            .handle_control(announce)
            .expect("announce should be accepted");
        assert_eq!(
            session.peer_moss_id.as_deref(),
            Some(peer_id.as_str()),
            "the announce is what relearns the counterpart"
        );
        assert!(
            session.record_dirty,
            "the relearned id must be written back, or the next restart loses it again"
        );
    }

    // The announce is a repair path: it must fire only while the id is missing,
    // and must not flood while it is.
    #[test]
    fn peer_announce_fires_only_while_the_id_is_missing() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let (mut alice, session_id) = lone_session(42164);
        let session = alice
            .sessions
            .get_mut(&session_id)
            .expect("Alice session should exist");

        session.peer_joined = true;
        session.peer_moss_id = Some("ab".repeat(32));
        session.pump_peer_announce(10_000);
        assert_eq!(
            session.last_peer_announce_ms, 0,
            "a session that knows its peer never announces"
        );

        session.peer_moss_id = None;
        session.pump_peer_announce(10_000);
        assert_eq!(session.last_peer_announce_ms, 10_000);

        session.pump_peer_announce(10_000 + PEER_ANNOUNCE_RESEND_MS - 1);
        assert_eq!(
            session.last_peer_announce_ms, 10_000,
            "announces inside the throttle window are suppressed"
        );

        let due = 10_000 + PEER_ANNOUNCE_RESEND_MS;
        session.pump_peer_announce(due);
        assert_eq!(session.last_peer_announce_ms, due);
    }

    // Regression: peer_moss_id was not persisted, and nothing relearns it after
    // the handshake completes (pump_handshake only resends while !peer_joined).
    // A restarted client therefore fell into the unknown-id fallback forever:
    // Connected against strangers, no dial target, and no addressable relayed
    // send. The record is finalized before the id is learned, so this also
    // covers the dirty-record rewrite.
    #[test]
    fn peer_moss_id_survives_a_restart() {
        use crate::persistence::Persistence;
        use std::path::PathBuf;

        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!("mosh-dm-peer-id-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [23u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let peer_id = "ab".repeat(32);

        let session_id = {
            let mut alice = PrivateDmRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            let invite = alice
                .create_invite(StartSessionRequest {
                    display_name: "Alice".to_string(),
                    listen_port: 42162,
                    static_peer: None,
                })
                .expect("Alice invite should be created");

            // What handle_control does with the peer's KeyPackage. Alice's MLS
            // group already exists, so the record was finalized at invite time.
            alice
                .sessions
                .get_mut(&invite.session_id)
                .expect("Alice session should exist")
                .note_peer_moss_id(Some(peer_id.clone()));
            alice
                .poll_session(&invite.session_id)
                .expect("poll should re-persist the dirtied record");
            invite.session_id
        };

        let mut revived =
            PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
        revived.rehydrate();
        let session = revived
            .sessions
            .get(&session_id)
            .expect("session should rehydrate");
        assert_eq!(
            session.peer_moss_id.as_deref(),
            Some(peer_id.as_str()),
            "the restored session must still know which peer is its counterpart"
        );

        let _ = std::fs::remove_file(&db_path);
    }

    // Regression: the invite *joiner* (Bob) only obtains an MLS group after he
    // processes Alice's Welcome, so his persisted session record must be
    // refreshed with the real group_id once joined. Otherwise rehydrate cannot
    // load the group and the whole conversation is silently dropped on restart.
    //
    // Needs a real two-node loopback handshake, which is timing-flaky, so it is
    // on-demand (`cargo test -- --ignored`). The group_id-refresh logic itself
    // is also exercised by the crypto restore tests.
    #[test]
    #[ignore]
    fn joiner_history_and_session_survive_restart() {
        use crate::persistence::Persistence;
        use std::path::PathBuf;

        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!(
            "mosh-dm-joiner-rehydrate-{}.redb",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&db_path);

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        // Alice (creator) is memory-only; Bob (joiner) is the one that persists.
        let bob_store =
            Arc::new(Persistence::open_with_dek(&db_path, [7u8; 32]).expect("store should open"));

        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42150,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let session_id = {
            let mut bob = PrivateDmRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(bob_store.clone()),
            );
            bob.accept_invite(AcceptInviteRequest {
                invite_uri: invite.invite_uri.clone(),
                display_name: "Bob".to_string(),
                listen_port: 42151,
                static_peer: Some("127.0.0.1:42150".to_string()),
            })
            .expect("Bob should accept invite");

            wait_until_ready(&mut alice, &mut bob, &invite.session_id);
            bob.send_message(&invite.session_id, "joiner persists".to_string())
                .expect("Bob should send");
            invite.session_id.clone()
        };

        // Bob "restarts": brand-new runtime, same encrypted store.
        let mut revived =
            PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(bob_store));
        revived.rehydrate();

        let listing = revived.list_sessions().expect("listing should pass");
        let session = listing
            .sessions
            .iter()
            .find(|s| s.session_id == session_id)
            .expect("rehydrated joiner session should be present");
        assert!(
            session.messages.iter().any(|m| m.body == "joiner persists"),
            "joiner message lost across restart: {:?}",
            session.messages
        );

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn private_dm_inbound_filter_includes_voice_call_channels() {
        assert!(transport::is_private_dm_inbound("mls-control/session-one"));
        assert!(transport::is_private_dm_inbound("mls-data/session-one"));
        assert!(transport::is_private_dm_inbound("mls-blob/session-one"));
        assert!(transport::is_private_dm_inbound("voice-call/call-one"));
        assert!(!transport::is_private_dm_inbound("public-channel/general"));
    }

    // Real Moss call E2E. This exercises the voice-call subscription and
    // frame routing path, but local peer handshakes are timing-sensitive in
    // the full suite, so run it explicitly when touching call transport.
    #[test]
    #[ignore]
    fn private_dm_runtime_routes_voice_call_frames_over_moss() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42134,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42135,
            static_peer: Some("127.0.0.1:42134".to_string()),
        })
        .expect("Bob should accept invite");

        wait_until_ready(&mut alice, &mut bob, &invite.session_id);
        let call = alice
            .call_start(&invite.session_id)
            .expect("Alice should start a call");
        wait_for_pending_call(&mut bob, &invite.session_id, &call.call_id);
        bob.call_accept(&invite.session_id, &call.call_id)
            .expect("Bob should accept the call");
        wait_for_active_call(&mut alice, &mut bob, &invite.session_id, &call.call_id);

        alice
            .call_send_frame(
                &invite.session_id,
                &call.call_id,
                test_call_frame(0, &[1, 2, 3]),
            )
            .expect("Alice should send a voice frame");
        assert_eq!(
            wait_for_call_frame(&mut bob, &invite.session_id, &call.call_id),
            test_call_frame(0, &[1, 2, 3])
        );

        bob.call_send_frame(
            &invite.session_id,
            &call.call_id,
            test_call_frame(1 << 63, &[4, 5, 6]),
        )
        .expect("Bob should send a voice frame");
        assert_eq!(
            wait_for_call_frame(&mut alice, &invite.session_id, &call.call_id),
            test_call_frame(1 << 63, &[4, 5, 6])
        );
    }

    // Heavy end-to-end transfer over real Moss. Loading the Moss Go runtime
    // a third time in one process makes the handshake flaky under suite
    // load, so this runs on demand via `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn private_dm_runtime_transfers_attachment_over_moss() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42132,
                static_peer: None,
            })
            .expect("Alice invite should be created");

        let receiver_store = temp_store();
        let mut bob = PrivateDmRuntime::from_shared(runtime, Arc::clone(&receiver_store), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42133,
            static_peer: Some("127.0.0.1:42132".to_string()),
        })
        .expect("Bob should accept invite");

        wait_until_ready(&mut alice, &mut bob, &invite.session_id);

        let payload: Vec<u8> = (0..(CHUNK_SIZE as usize) * 2 + 123)
            .map(|index| (index % 251) as u8)
            .collect();
        let send = alice
            .send_attachment(
                &invite.session_id,
                "photo.bin".to_string(),
                "application/octet-stream".to_string(),
                payload.clone(),
                None,
                None,
            )
            .expect("Alice should send attachment");

        let attachment_id = wait_for_attachment(&mut bob, &invite.session_id, &send.attachment_id);
        bob.download_attachment(&invite.session_id, &attachment_id)
            .expect("Bob should start download");

        wait_for_attachment_available(&mut alice, &mut bob, &invite.session_id, &attachment_id);
        let stored = receiver_store
            .read_blob(&send.content_hash, "photo.bin")
            .expect("Bob should have stored the blob");
        assert_eq!(stored, payload);
    }

    fn wait_for_attachment(
        runtime: &mut PrivateDmRuntime,
        session_id: &str,
        attachment_id: &str,
    ) -> String {
        for _ in 0..40 {
            let snapshot = runtime.poll_session(session_id).expect("poll should pass");
            if snapshot
                .attachments
                .iter()
                .any(|view| view.attachment_id == attachment_id)
            {
                return attachment_id.to_string();
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("attachment manifest did not arrive");
    }

    fn wait_for_attachment_available(
        alice: &mut PrivateDmRuntime,
        bob: &mut PrivateDmRuntime,
        session_id: &str,
        attachment_id: &str,
    ) {
        for _ in 0..120 {
            let _ = alice.poll_session(session_id);
            let snapshot = bob.poll_session(session_id).expect("poll should pass");
            if snapshot.attachments.iter().any(|view| {
                view.attachment_id == attachment_id && view.state == AttachmentState::Available
            }) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("attachment did not finish downloading");
    }

    fn wait_until_ready(
        alice: &mut PrivateDmRuntime,
        bob: &mut PrivateDmRuntime,
        session_id: &str,
    ) {
        // The Moss handshake is timing-sensitive; allow generous headroom so
        // the test stays green under full-suite CPU contention.
        for _ in 0..200 {
            let alice_ready = alice
                .poll_session(session_id)
                .expect("Alice poll should pass")
                .state
                == DmSessionState::Connected;
            let bob_ready = bob
                .poll_session(session_id)
                .expect("Bob poll should pass")
                .state
                == DmSessionState::Connected;
            if alice_ready && bob_ready {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        panic!("sessions did not become ready");
    }

    fn wait_for_pending_call(runtime: &mut PrivateDmRuntime, session_id: &str, call_id: &str) {
        for _ in 0..60 {
            let snapshot = runtime.poll_session(session_id).expect("poll should pass");
            if snapshot
                .pending_call
                .as_ref()
                .is_some_and(|call| call.call_id == call_id)
            {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("pending call did not arrive");
    }

    fn wait_for_active_call(
        alice: &mut PrivateDmRuntime,
        bob: &mut PrivateDmRuntime,
        session_id: &str,
        call_id: &str,
    ) {
        for _ in 0..60 {
            let alice_active = alice
                .poll_session(session_id)
                .expect("Alice poll should pass")
                .active_call
                .as_ref()
                .is_some_and(|call| call.call_id == call_id);
            let bob_active = bob
                .poll_session(session_id)
                .expect("Bob poll should pass")
                .active_call
                .as_ref()
                .is_some_and(|call| call.call_id == call_id);
            if alice_active && bob_active {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("call did not become active");
    }

    fn wait_for_call_frame(
        runtime: &mut PrivateDmRuntime,
        session_id: &str,
        call_id: &str,
    ) -> Vec<u8> {
        for _ in 0..60 {
            let frames = runtime
                .call_drain_frames(session_id, call_id)
                .expect("frame drain should pass");
            if let Some(frame) = frames.into_iter().next() {
                return frame;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        panic!("voice frame did not arrive");
    }

    fn test_call_frame(seq: u64, payload: &[u8]) -> Vec<u8> {
        let mut frame = seq.to_be_bytes().to_vec();
        frame.extend_from_slice(payload);
        frame
    }

    fn wait_for_message(
        runtime: &mut PrivateDmRuntime,
        session_id: &str,
        body: &str,
    ) -> SessionSnapshot {
        for _ in 0..30 {
            let snapshot = runtime.poll_session(session_id).expect("poll should pass");
            if snapshot.messages.iter().any(|message| message.body == body) {
                return snapshot;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        panic!("message did not arrive");
    }

    // Two conversations share the one node the holder keeps, and the node
    // goes down with the last of them. Two nodes would present the same peer
    // id from two ports and a remote peer would keep one.
    #[test]
    fn sessions_share_one_node_and_close_releases_it() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let holder = SharedMossNode::new(runtime);
        let mut alice = PrivateDmRuntime::from_shared_node(Arc::clone(&holder), temp_store(), None);
        let first = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42187,
                static_peer: None,
            })
            .expect("first invite should be created");
        let node_ptr = Arc::as_ptr(&holder.current().expect("the node is up"));
        let second = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42188,
                static_peer: None,
            })
            .expect("second invite should be created");
        assert_eq!(
            node_ptr,
            Arc::as_ptr(&holder.current().expect("the node is still up")),
            "the second conversation started a second moss node"
        );
        assert_ne!(
            alice.sessions[&first.session_id].mesh_id, alice.sessions[&second.session_id].mesh_id,
            "sessions must stay in separate rooms on the shared node"
        );

        // Closing one leaves the node up for the other...
        alice
            .close_session(&first.session_id)
            .expect("first session should close");
        assert!(
            holder.current().is_some(),
            "the shared node went down while a conversation was still open"
        );
        // ...and closing the last one takes it down.
        alice
            .close_session(&second.session_id)
            .expect("second session should close");
        assert!(
            holder.current().is_none(),
            "the shared node outlived every conversation — nothing would ever stop moss"
        );
    }

    // Real two-node loopback: one node per installation serves the handshake
    // and a message, and no second node ever appears. Every snapshot along
    // the way names the substrate room, which only the one node is born in.
    // Timing-sensitive like the other loopback tests, so on demand
    // (`cargo test -- --ignored`).
    #[test]
    #[ignore]
    fn one_node_serves_the_handshake_and_a_message() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut alice = PrivateDmRuntime::from_shared(Arc::clone(&runtime), temp_store(), None);
        let invite = alice
            .create_invite(StartSessionRequest {
                display_name: "Alice".to_string(),
                listen_port: 42132,
                static_peer: None,
            })
            .expect("Alice invite should be created");
        let mut bob = PrivateDmRuntime::from_shared(runtime, temp_store(), None);
        bob.accept_invite(AcceptInviteRequest {
            invite_uri: invite.invite_uri.clone(),
            display_name: "Bob".to_string(),
            listen_port: 42133,
            static_peer: Some("127.0.0.1:42132".to_string()),
        })
        .expect("Bob should accept invite");

        wait_until_ready(&mut alice, &mut bob, &invite.session_id);
        alice
            .send_message(&invite.session_id, "one node".to_string())
            .expect("Alice should send");
        let snapshot = wait_for_message(&mut bob, &invite.session_id, "one node");

        for view in [
            snapshot,
            alice
                .poll_session(&invite.session_id)
                .expect("Alice poll should pass"),
        ] {
            assert_eq!(view.state, DmSessionState::Connected);
            assert_ne!(view.transport, PeerTransport::None);
            assert_eq!(
                view.mesh.expect("the node reports").mesh_id,
                crate::shared_node::SUBSTRATE_ROOM,
                "a DM frame went through a node born in some other mesh"
            );
        }
    }
}
