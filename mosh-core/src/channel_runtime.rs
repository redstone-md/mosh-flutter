use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::attachment_crypto::sha256_hex;
use crate::attachment_runtime::{
    AttachmentManifest, AttachmentRuntime, ChunkFrame, ChunkOutcome, ChunkRequest,
    OutgoingAttachment, StreamRange, VoiceMeta,
};
use crate::attachment_store::AttachmentStore;
use crate::conversation::attachments::{
    descriptor_of, AttachmentDescriptor, AttachmentSendResult, AttachmentSlots, AttachmentView,
    SlotError,
};
use crate::conversation::dedup::SeenFrames;
use crate::conversation::dm_offers::{DmOffer, DmOffers};
use crate::conversation::history::{History, Restore};
use crate::conversation::mesh::{self, MeshInfo, SnapshotEvent};
use crate::conversation::message_log::{ConversationMessage, LogError, MessageLog};
use crate::conversation::outbound::{OnSent, Outbox, Prepared};
use crate::moss_ffi::{drain_messages_where, MossFfiRuntime, MossNode, MossReceivedMessage};
use crate::outbound_delivery::{MessageDeliveryMeta, MessageDeliveryStatus, OutboundAttemptRecord};
use crate::persistence::{Persistence, CHANNEL_HISTORY};
use crate::shared_node::SharedMossNode;

const TOPIC_PREFIX: &str = "public-channel/";
const BLOB_PREFIX: &str = "channel-blob/";
const MESH_PREFIX: &str = "channel/";
const MAX_NAME_LEN: usize = 64;
const MAX_BODY_LEN: usize = 4096;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinChannelRequest {
    pub name: String,
    pub display_name: String,
    pub listen_port: u16,
    pub static_peer: Option<String>,
}

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
enum ChannelBlobEnvelope {
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
struct PersistedChannelSession {
    name: String,
    topic: String,
    blob_topic: String,
    mesh_id: String,
    display_name: String,
    device_fingerprint: String,
    listen_port: u16,
    static_peer: Option<String>,
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

impl From<crate::attachment_runtime::AttachmentRuntimeError> for ChannelRuntimeError {
    fn from(error: crate::attachment_runtime::AttachmentRuntimeError) -> Self {
        Self::Attachment(error.to_string())
    }
}

impl From<crate::attachment_store::AttachmentStoreError> for ChannelRuntimeError {
    fn from(error: crate::attachment_store::AttachmentStoreError) -> Self {
        Self::Attachment(error.to_string())
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
    shared_node: Arc<SharedMossNode>,
    attachment_store: Arc<AttachmentStore>,
    persistence: Option<Arc<Persistence>>,
    history: History,
    channels: HashMap<String, ChannelSession>,
}

struct ChannelSession {
    name: String,
    topic: String,
    blob_topic: String,
    mesh_id: String,
    display_name: String,
    device_fingerprint: String,
    listen_port: u16,
    static_peer: Option<String>,
    node: Arc<MossNode>,
    messages: MessageLog<ChannelMessage>,
    seen: SeenFrames,
    attachment_store: Arc<AttachmentStore>,
    attachments: AttachmentRuntime,
    attachment_slots: AttachmentSlots,
    outbound_attempts: HashMap<String, OutboundAttemptRecord>,
    dm_offers: DmOffers,
}

impl ChannelRuntime {
    pub fn new(moss: MossFfiRuntime, attachment_store: Arc<AttachmentStore>) -> Self {
        Self::from_shared(Arc::new(moss), attachment_store, None)
    }

    pub fn from_shared(
        moss: Arc<MossFfiRuntime>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        Self::from_shared_node(SharedMossNode::new(moss), attachment_store, persistence)
    }

    /// The constructor a real client uses: every runtime in the process is
    /// handed the SAME holder, so channels share their node with DMs, groups
    /// and orgs. `from_shared` mints a private holder, which is what tests
    /// running two peers in one process need.
    pub fn from_shared_node(
        shared_node: Arc<SharedMossNode>,
        attachment_store: Arc<AttachmentStore>,
        persistence: Option<Arc<Persistence>>,
    ) -> Self {
        Self {
            shared_node,
            attachment_store,
            persistence,
            history: History::new(CHANNEL_HISTORY),
            channels: HashMap::new(),
        }
    }

    /// Take a reference to the shared node and put this channel's room on it.
    /// Rolls the reference back if the room work fails, so a channel that never
    /// opened cannot pin the node up forever.
    fn open_channel_room(
        &mut self,
        mesh_id: &str,
        topic: &str,
        blob_topic: &str,
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<Arc<MossNode>, ChannelRuntimeError> {
        let node = self
            .shared_node
            .acquire(listen_port, static_peer)
            .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))?;
        if let Err(error) = join_channel_room(&node, mesh_id, topic, blob_topic) {
            self.shared_node.release();
            return Err(error);
        }
        Ok(node)
    }

    /// Restore joined public channels and local scrollback from encrypted disk.
    pub fn rehydrate(&mut self) {
        let Some(p) = self.persistence.as_ref().cloned() else {
            return;
        };
        for rec in self
            .history
            .stored_conversations::<PersistedChannelSession>(&p)
        {
            let node = match self.open_channel_room(
                &rec.mesh_id,
                &rec.topic,
                &rec.blob_topic,
                rec.listen_port,
                rec.static_peer.clone(),
            ) {
                Ok(node) => node,
                Err(error) => {
                    eprintln!(
                        "channel rehydrate: node start failed for {}: {error}",
                        rec.name
                    );
                    continue;
                }
            };
            let mut session = ChannelSession {
                name: rec.name.clone(),
                topic: rec.topic.clone(),
                blob_topic: rec.blob_topic.clone(),
                mesh_id: rec.mesh_id.clone(),
                display_name: rec.display_name.clone(),
                device_fingerprint: node
                    .public_key_hex()
                    .unwrap_or_else(|| rec.device_fingerprint.clone()),
                listen_port: rec.listen_port,
                static_peer: rec.static_peer.clone(),
                node,
                messages: MessageLog::default(),
                seen: SeenFrames::default(),
                attachment_store: Arc::clone(&self.attachment_store),
                attachments: AttachmentRuntime::new(),
                attachment_slots: AttachmentSlots::default(),
                outbound_attempts: HashMap::new(),
                dm_offers: DmOffers::default(),
            };
            self.history.replay(
                &p,
                &rec.name,
                Restore {
                    log: &mut session.messages,
                    attempts: &mut session.outbound_attempts,
                    slots: &mut session.attachment_slots,
                    attachment_store: &self.attachment_store,
                    local_author: &rec.device_fingerprint,
                },
            );
            self.channels.insert(rec.name, session);
        }
    }

    pub fn join(
        &mut self,
        request: JoinChannelRequest,
    ) -> Result<ChannelSnapshot, ChannelRuntimeError> {
        let normalized = normalize_name(&request.name)?;
        if self.channels.contains_key(&normalized) {
            return Err(ChannelRuntimeError::DuplicateChannel(normalized));
        }
        let listen_port = request.listen_port;
        let static_peer = request.static_peer.clone();

        let mesh_id = format!("{MESH_PREFIX}{normalized}");
        let topic = format!("{TOPIC_PREFIX}{normalized}");
        let blob_topic = format!("{BLOB_PREFIX}{normalized}");
        let node = self.open_channel_room(
            &mesh_id,
            &topic,
            &blob_topic,
            listen_port,
            static_peer.clone(),
        )?;
        let device_fingerprint = node
            .public_key_hex()
            .ok_or_else(|| ChannelRuntimeError::Moss("public key unavailable".to_string()))?;

        let session = ChannelSession {
            name: normalized.clone(),
            topic,
            blob_topic,
            mesh_id,
            display_name: request.display_name,
            device_fingerprint,
            listen_port,
            static_peer,
            node,
            messages: MessageLog::default(),
            seen: SeenFrames::default(),
            attachment_store: Arc::clone(&self.attachment_store),
            attachments: AttachmentRuntime::new(),
            attachment_slots: AttachmentSlots::default(),
            outbound_attempts: HashMap::new(),
            dm_offers: DmOffers::default(),
        };

        self.channels.insert(normalized.clone(), session);
        self.persist_channel_tail();
        self.poll(&normalized)
    }

    /// Publishes a private-DM invitation aimed at one channel member.
    pub fn send_dm_offer(
        &mut self,
        name: &str,
        target_fingerprint: String,
        invite_uri: String,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        let offer = DmOffers::mint(
            session.display_name.clone(),
            session.device_fingerprint.clone(),
            target_fingerprint,
            invite_uri,
        );
        publish_json(
            &session.node,
            &session.mesh_id,
            &session.blob_topic,
            &ChannelBlobEnvelope::DmOffer { offer },
        )
    }

    pub fn dismiss_dm_offer(
        &mut self,
        name: &str,
        offer_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        session.dm_offers.dismiss(offer_id);
        Ok(())
    }

    pub fn leave(&mut self, name: &str) -> Result<ChannelLeaveResult, ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        match self.channels.remove(&normalized) {
            Some(session) => {
                // On a shared node dropping the session no longer ends its
                // subscriptions — the node lives on for the other channels, so
                // leaving has to be said out loud or a left channel keeps
                // receiving.
                leave_channel_room(&session);
                self.shared_node.release();
                self.history.forget(&normalized);
                if let Some(p) = self.persistence.as_ref() {
                    if let Err(error) = p.delete_channel(&normalized) {
                        eprintln!("failed to delete persisted channel {normalized}: {error}");
                    }
                }
                Ok(ChannelLeaveResult {
                    name: normalized,
                    closed: true,
                })
            }
            None => Err(ChannelRuntimeError::MissingChannel(normalized)),
        }
    }

    pub fn send(
        &mut self,
        name: &str,
        body: String,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        if body.len() > MAX_BODY_LEN {
            return Err(ChannelRuntimeError::BodyTooLarge);
        }
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let (channel_name, topic, prepared) = {
            let session = self
                .channels
                .get_mut(&normalized)
                .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
            let message = session.messages.stamp(ChannelMessage {
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
            // A channel is public, so the frame is the message itself, minus
            // the delivery fields that only mean something to the sender.
            let payload = serde_json::to_vec(&session.publishable_message(&message))
                .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
            let bytes = payload.len();
            let channel_name = session.name.clone();
            let topic = session.topic.clone();
            let prepared = session
                .outbox()
                .open(message, channel_name.clone(), payload, bytes)?;
            (channel_name, topic, prepared)
        };
        let result = self.publish_prepared(&normalized, &topic, channel_name, prepared)?;
        self.persist_channel_tail();
        Ok(result)
    }

    pub fn retry_message(
        &mut self,
        name: &str,
        message_id: &str,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let (channel_name, topic, prepared) = {
            let session = self
                .channels
                .get_mut(&normalized)
                .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
            let prepared = session.outbox().reopen(message_id)?;
            (session.name.clone(), session.topic.clone(), prepared)
        };
        let result = self.publish_prepared(&normalized, &topic, channel_name, prepared)?;
        self.persist_channel_tail();
        Ok(result)
    }

    /// Publishes a prepared send on the channel's topic and writes down how it
    /// went. A channel has no acknowledgement, so the attempt record is gone
    /// as soon as the frame is on the wire.
    fn publish_prepared(
        &mut self,
        normalized: &str,
        topic: &str,
        channel_name: String,
        prepared: Prepared,
    ) -> Result<ChannelSendResult, ChannelRuntimeError> {
        self.persist_outbound_state(normalized, &prepared.message_id);
        let publish = {
            let session = self
                .channels
                .get(normalized)
                .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.to_string()))?;
            session
                .node
                .publish_room(&session.mesh_id, topic, &prepared.payload)
                .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))
        };
        let settled = {
            let session = self
                .channels
                .get_mut(normalized)
                .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.to_string()))?;
            session.outbox().settle(
                &prepared.message_id,
                publish.map_err(|error| error.to_string()),
                OnSent::Forget,
            )?
        };
        self.persist_outbound_state(normalized, &prepared.message_id);
        Ok(ChannelSendResult {
            name: channel_name,
            bytes: prepared.ciphertext_bytes,
            message_id: prepared.message_id,
            sent_at_ms: prepared.sent_at_ms,
            delivery_status: settled.status,
            delivery_error: settled.error,
        })
    }

    /// Encrypts a file, stores the sender's copy, and broadcasts the manifest
    /// on the channel's plaintext blob topic.
    pub fn send_attachment(
        &mut self,
        name: &str,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        let result = session.send_attachment(file_name, mime, bytes, thumbnail, voice)?;
        self.persist_channel_tail();
        Ok(result)
    }

    pub fn download_attachment(
        &mut self,
        name: &str,
        attachment_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        session
            .attachment_slots
            .start_download(attachment_id, &mut session.attachments)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        name: &str,
        attachment_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        Ok(session
            .attachment_slots
            .cancel(attachment_id, &mut session.attachments)?)
    }

    /// Serves a byte range for streaming playback of a channel attachment.
    pub fn stream_attachment_range(
        &mut self,
        name: &str,
        attachment_id: &str,
        start: u64,
        end: u64,
    ) -> Result<StreamRange, ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get_mut(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        session
            .attachment_slots
            .resume_for_stream(attachment_id, &mut session.attachments);
        let outcome = session.attachments.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }

    pub fn poll(&mut self, name: &str) -> Result<ChannelSnapshot, ChannelRuntimeError> {
        self.drain_inbound()?;
        self.persist_channel_tail();
        let normalized = normalize_name(name)?;
        let session = self
            .channels
            .get(&normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.clone()))?;
        Ok(session.snapshot())
    }

    pub fn list(&mut self) -> Result<ChannelListSnapshot, ChannelRuntimeError> {
        self.drain_inbound()?;
        self.persist_channel_tail();
        let mut channels: Vec<ChannelSnapshot> = self
            .channels
            .values()
            .map(ChannelSession::snapshot)
            .collect();
        channels.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(ChannelListSnapshot { channels })
    }

    pub fn drain_inbound(&mut self) -> Result<(), ChannelRuntimeError> {
        let inbound = drain_messages_where(|message| {
            channel_name_from_topic(&message.channel).is_some()
                || channel_name_from_blob(&message.channel).is_some()
        });
        for message in inbound {
            let name = channel_name_from_topic(&message.channel)
                .or_else(|| channel_name_from_blob(&message.channel))
                .map(|value| value.to_string());
            let Some(name) = name else {
                continue;
            };
            if let Some(session) = self.channels.get_mut(&name) {
                session.handle_message(message)?;
            }
        }
        for session in self.channels.values_mut() {
            session.pump_attachment_requests();
        }
        Ok(())
    }

    fn persist_channel_tail(&mut self) {
        let Some(p) = self.persistence.as_ref().cloned() else {
            return;
        };
        for session in self.channels.values() {
            self.history
                .write_tail(&p, &session.name, &session.messages);
            self.history
                .write_record(&p, &session.name, &session.to_persisted_record());
        }
    }

    fn persist_outbound_state(&mut self, name: &str, message_id: &str) {
        let Some(p) = self.persistence.as_ref().cloned() else {
            return;
        };
        let Some(session) = self.channels.get(name) else {
            return;
        };
        if !self.history.write_send(
            &p,
            name,
            message_id,
            &session.messages,
            &session.outbound_attempts,
        ) {
            return;
        }
        self.history
            .write_record(&p, name, &session.to_persisted_record());
    }
}

impl ChannelSession {
    fn publishable_message(&self, message: &ChannelMessage) -> ChannelMessage {
        let mut publishable = message.clone();
        publishable.delivery_status = None;
        publishable.delivery_error = None;
        publishable.retryable = None;
        publishable.retry_count = None;
        publishable
    }

    /// The message log and the attempts in flight, borrowed together for one
    /// step of a send.
    fn outbox(&mut self) -> Outbox<'_, ChannelMessage> {
        Outbox::new(&mut self.messages, &mut self.outbound_attempts)
    }

    fn to_persisted_record(&self) -> PersistedChannelSession {
        PersistedChannelSession {
            name: self.name.clone(),
            topic: self.topic.clone(),
            blob_topic: self.blob_topic.clone(),
            mesh_id: self.mesh_id.clone(),
            display_name: self.display_name.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            listen_port: self.listen_port,
            static_peer: self.static_peer.clone(),
        }
    }

    fn handle_message(&mut self, message: MossReceivedMessage) -> Result<(), ChannelRuntimeError> {
        if self.seen.seen_before(&message.channel, &message.payload) {
            return Ok(());
        }
        if message.channel == self.topic {
            let envelope: ChannelMessage = serde_json::from_slice(&message.payload)
                .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
            if self.messages.holds_copy_of(&envelope) {
                return Ok(());
            }
            if envelope.from_fingerprint == self.device_fingerprint {
                return Ok(());
            }
            self.messages.push_stamped(envelope);
            Ok(())
        } else if message.channel == self.blob_topic {
            self.handle_blob(message.payload)
        } else {
            Ok(())
        }
    }

    fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), ChannelRuntimeError> {
        let envelope: ChannelBlobEnvelope = serde_json::from_slice(&payload)
            .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
        match envelope {
            ChannelBlobEnvelope::Manifest {
                from_device,
                from_fingerprint,
                manifest,
            } if from_fingerprint != self.device_fingerprint => {
                self.accept_incoming_manifest(from_device, from_fingerprint, manifest)
            }
            ChannelBlobEnvelope::Request {
                from_fingerprint,
                request,
            } if from_fingerprint != self.device_fingerprint => {
                let frames = match self.attachments.serve_chunks(&request) {
                    Ok(frames) => frames,
                    Err(_) => return Ok(()),
                };
                for frame in frames {
                    let chunk = ChannelBlobEnvelope::Chunk {
                        from_fingerprint: self.device_fingerprint.clone(),
                        frame,
                    };
                    publish_json(&self.node, &self.mesh_id, &self.blob_topic, &chunk)?;
                }
                Ok(())
            }
            ChannelBlobEnvelope::DmOffer { offer } => {
                self.dm_offers.receive(offer, &self.device_fingerprint);
                Ok(())
            }
            ChannelBlobEnvelope::Chunk {
                from_fingerprint,
                frame,
            } if from_fingerprint != self.device_fingerprint => {
                let attachment_id = frame.attachment_id.clone();
                let file_name = self.attachment_slots.file_name(&attachment_id);
                match self.attachments.ingest_chunk(&frame) {
                    Ok(ChunkOutcome::Complete {
                        content_hash,
                        bytes,
                        ..
                    }) => {
                        let path =
                            self.attachment_store
                                .write_blob(&content_hash, &file_name, &bytes)?;
                        self.attachment_slots
                            .complete_download(&attachment_id, path.to_string_lossy().into_owned());
                        Ok(())
                    }
                    Ok(_) => Ok(()),
                    Err(_) => {
                        self.attachment_slots.fail(&attachment_id);
                        Ok(())
                    }
                }
            }
            _ => Ok(()),
        }
    }

    fn accept_incoming_manifest(
        &mut self,
        from_device: String,
        from_fingerprint: String,
        manifest: AttachmentManifest,
    ) -> Result<(), ChannelRuntimeError> {
        let attachment_id = manifest.attachment_id.clone();
        if self.attachment_slots.contains(&attachment_id) {
            return Ok(());
        }
        let descriptor = descriptor_of(&manifest);
        self.attachments.register_incoming(manifest)?;
        self.attachment_slots.offer(descriptor.clone());
        let message = self.messages.stamp(ChannelMessage {
            from_device,
            from_fingerprint,
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: Some(descriptor),
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
    ) -> Result<AttachmentSendResult, ChannelRuntimeError> {
        let attachment_id = format!("attachment-{}", &sha256_hex(&bytes)[..16]);
        if self.attachment_slots.contains(&attachment_id) {
            return Err(ChannelRuntimeError::Attachment(
                "attachment already shared on this channel".to_string(),
            ));
        }
        let manifest = self.attachments.prepare_outgoing(OutgoingAttachment {
            attachment_id: attachment_id.clone(),
            file_name,
            mime,
            from_fingerprint: self.device_fingerprint.clone(),
            bytes: bytes.clone(),
            thumbnail_b64: thumbnail,
            voice,
        })?;
        let stored = self.attachment_store.write_blob(
            &manifest.content_hash,
            &manifest.file_name,
            &bytes,
        )?;
        let envelope = ChannelBlobEnvelope::Manifest {
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            manifest: manifest.clone(),
        };
        publish_json(&self.node, &self.mesh_id, &self.blob_topic, &envelope)?;

        let descriptor = descriptor_of(&manifest);
        self.attachment_slots
            .record_sent(descriptor.clone(), stored.to_string_lossy().into_owned());
        let message = self.messages.stamp(ChannelMessage {
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            body: String::new(),
            message_id: None,
            sent_at_ms: None,
            attachment: Some(descriptor),
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        self.messages.push(message);
        Ok(AttachmentSendResult {
            session_id: self.name.clone(),
            attachment_id,
            content_hash: manifest.content_hash,
        })
    }

    fn pump_attachment_requests(&mut self) {
        for attachment_id in self.attachment_slots.awaiting_chunks() {
            if let Some(request) = self.attachments.next_chunk_request(&attachment_id) {
                let envelope = ChannelBlobEnvelope::Request {
                    from_fingerprint: self.device_fingerprint.clone(),
                    request,
                };
                let _ = publish_json(&self.node, &self.mesh_id, &self.blob_topic, &envelope);
            }
        }
    }

    fn snapshot(&self) -> ChannelSnapshot {
        ChannelSnapshot {
            name: self.name.clone(),
            topic: self.topic.clone(),
            mesh_id: self.mesh_id.clone(),
            display_name: self.display_name.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            messages: self.messages.to_vec(),
            attachments: self.attachment_slots.views(&self.attachments),
            dm_offers: self.dm_offers.to_vec(),
            mesh: mesh::mesh_info(&self.node),
            events: mesh::snapshot_events(),
        }
    }
}

/// Puts a channel's room on the shared node and subscribes its two topics
/// there. Wire-identical to what a node owning that room published before, so a
/// consolidated client still talks to every already-released one.
fn join_channel_room(
    node: &MossNode,
    mesh_id: &str,
    topic: &str,
    blob_topic: &str,
) -> Result<(), ChannelRuntimeError> {
    node.join_room(mesh_id)
        .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))?;
    for channel in [topic, blob_topic] {
        node.subscribe_room(mesh_id, channel)
            .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))?;
    }
    Ok(())
}

/// The inverse of `join_channel_room`. Unsubscribe first, then forget the key:
/// leaving first would strand subscriptions that can no longer resolve.
fn leave_channel_room(session: &ChannelSession) {
    for channel in [&session.topic, &session.blob_topic] {
        if let Err(error) = session.node.unsubscribe_room(&session.mesh_id, channel) {
            eprintln!(
                "channel {} could not unsubscribe {channel}: {error}",
                session.name
            );
        }
    }
    if let Err(error) = session.node.leave_room(&session.mesh_id) {
        eprintln!("channel {} could not leave its room: {error}", session.name);
    }
}

pub fn normalize_name(raw: &str) -> Result<String, ChannelRuntimeError> {
    let trimmed = raw.trim().trim_start_matches('#').trim_start_matches('@');
    if trimmed.is_empty() || trimmed.len() > MAX_NAME_LEN {
        return Err(ChannelRuntimeError::InvalidName(raw.to_string()));
    }
    let normalized: String = trimmed.chars().map(|c| c.to_ascii_lowercase()).collect();
    if !normalized
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(ChannelRuntimeError::InvalidName(raw.to_string()));
    }
    Ok(normalized)
}

fn channel_name_from_topic(topic: &str) -> Option<&str> {
    topic.strip_prefix(TOPIC_PREFIX)
}

fn channel_name_from_blob(topic: &str) -> Option<&str> {
    topic.strip_prefix(BLOB_PREFIX)
}

/// Always room-scoped: the shared node's own room is the substrate, so a
/// room-less publish would land where none of this channel's peers listen.
fn publish_json<T: Serialize>(
    node: &MossNode,
    mesh_id: &str,
    topic: &str,
    value: &T,
) -> Result<(), ChannelRuntimeError> {
    let payload =
        serde_json::to_vec(value).map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
    node.publish_room(mesh_id, topic, &payload)
        .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::moss_ffi::{
        drain_received_messages, fail_next_test_publish, MossFfiRuntime, MOSS_TEST_LOCK,
    };
    use crate::persistence::Persistence;
    use std::path::PathBuf;

    fn temp_store() -> Arc<AttachmentStore> {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "mosh-channel-attachments-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        Arc::new(AttachmentStore::new(&path).expect("attachment store should init"))
    }

    #[test]
    fn normalize_strips_prefix_and_lowercases() {
        assert_eq!(normalize_name("@MOSH-DEV").unwrap(), "mosh-dev");
        assert_eq!(normalize_name("#general_chat").unwrap(), "general_chat");
        assert_eq!(normalize_name("  spaced  ").unwrap(), "spaced");
    }

    #[test]
    fn normalize_rejects_invalid_input() {
        assert!(normalize_name("").is_err());
        assert!(normalize_name("with spaces").is_err());
        assert!(normalize_name("emoji😀").is_err());
        assert!(normalize_name(&"a".repeat(MAX_NAME_LEN + 1)).is_err());
    }

    #[test]
    fn channel_name_strips_topic_prefix() {
        assert_eq!(
            channel_name_from_topic("public-channel/mosh-dev"),
            Some("mosh-dev")
        );
        assert_eq!(channel_name_from_topic("mls-control/sid"), None);
    }

    // Every joined channel now shares one moss node, so a channel's own room is
    // what separates it from the others — and the node outliving the channel is
    // a new failure mode: nothing ends its subscriptions unless leave says so.
    #[test]
    fn channels_share_one_node_and_leave_releases_it() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));
        let mut channels = ChannelRuntime::from_shared(runtime, temp_store(), None);
        for (name, port) in [("shared-one", 42360u16), ("shared-two", 42361)] {
            channels
                .join(JoinChannelRequest {
                    name: name.to_string(),
                    display_name: "Alice".to_string(),
                    listen_port: port,
                    static_peer: None,
                })
                .unwrap_or_else(|error| panic!("{name} should join: {error}"));
        }

        // One node, not two. Two would present the same peer id from two ports
        // and a remote peer would keep only the first.
        let first = Arc::as_ptr(&channels.channels["shared-one"].node);
        let second = Arc::as_ptr(&channels.channels["shared-two"].node);
        assert_eq!(
            first, second,
            "two joined channels started two moss nodes under one identity"
        );
        assert_ne!(
            channels.channels["shared-one"].mesh_id, channels.channels["shared-two"].mesh_id,
            "channels must stay in separate rooms on the shared node"
        );

        channels.leave("shared-one").expect("first should leave");
        assert!(
            channels.shared_node.current().is_some(),
            "the shared node went down while a channel was still joined"
        );
        channels.leave("shared-two").expect("second should leave");
        assert!(
            channels.shared_node.current().is_none(),
            "the shared node outlived every channel — nothing would ever stop moss"
        );
    }

    #[test]
    fn channel_history_survives_restart_without_duplicate_tail() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!(
            "mosh-channel-rehydrate-{}.redb",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [16u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        {
            let mut channels = ChannelRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            channels
                .join(JoinChannelRequest {
                    name: "restart-channel".to_string(),
                    display_name: "Alice".to_string(),
                    listen_port: 42340,
                    static_peer: None,
                })
                .expect("channel should join");
            channels
                .send("restart-channel", "hello after channel restart".to_string())
                .expect("channel message should send");
        }

        let mut revived = ChannelRuntime::from_shared(
            Arc::clone(&runtime),
            temp_store(),
            Some(persistence.clone()),
        );
        revived.rehydrate();

        let listing = revived.list().expect("listing should pass");
        let channel = listing
            .channels
            .iter()
            .find(|channel| channel.name == "restart-channel")
            .expect("rehydrated channel should be present");
        assert!(
            channel
                .messages
                .iter()
                .any(|message| message.body == "hello after channel restart"),
            "rehydrated channel message missing: {:?}",
            channel.messages
        );

        let listing2 = revived.list().expect("second listing should pass");
        let channel2 = listing2
            .channels
            .iter()
            .find(|channel| channel.name == "restart-channel")
            .expect("channel should still be present");
        let matching = channel2
            .messages
            .iter()
            .filter(|message| message.body == "hello after channel restart")
            .count();
        assert_eq!(matching, 1, "persist tail duplicated the channel message");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn failed_send_rehydrates_as_retryable_message() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!(
            "mosh-channel-failed-send-{}.redb",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [17u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        let message_id = {
            let mut channels = ChannelRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            channels
                .join(JoinChannelRequest {
                    name: "retry-channel".to_string(),
                    display_name: "Alice".to_string(),
                    listen_port: 42341,
                    static_peer: None,
                })
                .expect("channel should join");
            let _publish_fail = fail_next_test_publish("simulated publish failure");
            let result = channels
                .send("retry-channel", "hello failed channel".to_string())
                .expect("send should return failed result");
            assert_eq!(result.delivery_status, MessageDeliveryStatus::Failed);
            assert_eq!(
                result.delivery_error.as_deref(),
                Some("Moss error: simulated publish failure")
            );

            let live = channels
                .poll("retry-channel")
                .expect("poll should surface failed message");
            let failed = live
                .messages
                .iter()
                .find(|message| message.message_id.as_deref() == Some(result.message_id.as_str()))
                .expect("failed message should be recorded");
            assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
            assert_eq!(failed.retryable, Some(true));

            result.message_id
        };

        let mut revived =
            ChannelRuntime::from_shared(Arc::clone(&runtime), temp_store(), Some(persistence));
        revived.rehydrate();
        let listing = revived.list().expect("listing should pass");
        let channel = listing
            .channels
            .iter()
            .find(|channel| channel.name == "retry-channel")
            .expect("rehydrated channel should be present");
        let failed = channel
            .messages
            .iter()
            .find(|message| message.message_id.as_deref() == Some(message_id.as_str()))
            .expect("failed message should rehydrate");
        assert_eq!(failed.delivery_status, Some(MessageDeliveryStatus::Failed));
        assert_eq!(failed.retryable, Some(true));

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn retry_message_reuses_message_id_and_clears_failed_attempt() {
        let _guard = MOSS_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        drain_received_messages();

        let mut db_path: PathBuf = std::env::temp_dir();
        db_path.push(format!("mosh-channel-retry-{}.redb", std::process::id()));
        let _ = std::fs::remove_file(&db_path);

        let persistence =
            Arc::new(Persistence::open_with_dek(&db_path, [18u8; 32]).expect("store should open"));
        let runtime = Arc::new(MossFfiRuntime::load_default().expect("Moss runtime should load"));

        let failed_message_id = {
            let mut channels = ChannelRuntime::from_shared(
                Arc::clone(&runtime),
                temp_store(),
                Some(persistence.clone()),
            );
            channels
                .join(JoinChannelRequest {
                    name: "retry-channel".to_string(),
                    display_name: "Alice".to_string(),
                    listen_port: 42342,
                    static_peer: None,
                })
                .expect("channel should join");
            let _publish_fail = fail_next_test_publish("simulated publish failure");
            let failed = channels
                .send("retry-channel", "retry this channel message".to_string())
                .expect("failed send should still return a result");

            let retried = channels
                .retry_message("retry-channel", &failed.message_id)
                .expect("retry should succeed");
            assert_eq!(retried.message_id, failed.message_id);
            assert_eq!(retried.delivery_status, MessageDeliveryStatus::Sent);

            let snapshot = channels.poll("retry-channel").expect("poll should pass");
            let matching: Vec<&ChannelMessage> = snapshot
                .messages
                .iter()
                .filter(|message| message.message_id.as_deref() == Some(failed.message_id.as_str()))
                .collect();
            assert_eq!(
                matching.len(),
                1,
                "retry should update, not duplicate, the row"
            );
            assert_eq!(
                matching[0].delivery_status,
                Some(MessageDeliveryStatus::Sent)
            );
            assert_eq!(matching[0].retry_count, Some(1));

            failed.message_id
        };

        let stored_attempt = persistence
            .get_outbound_attempt("channel", "retry-channel", &failed_message_id)
            .expect("lookup should pass");
        assert!(stored_attempt.is_none());

        let _ = std::fs::remove_file(&db_path);
    }
}
