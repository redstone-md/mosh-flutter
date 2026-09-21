use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::attachment_crypto::sha256_hex;
use crate::attachment_runtime::{
    AttachmentManifest, ChunkFrame, ChunkRequest, OutgoingAttachment, StreamRange, VoiceMeta,
};
use crate::attachment_store::AttachmentStore;
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
use crate::diagnostics_log::{self as dlog, kinds, LogLevel};
use crate::inbox;
use crate::moss_ffi::{MossFfiRuntime, MossNode, MossReceivedMessage};
use crate::outbound_delivery::{MessageDeliveryMeta, MessageDeliveryStatus, OutboundAttemptRecord};
use crate::persistence::{Persistence, CHANNEL_HISTORY};
use crate::shared_node::SharedMossNode;

/// What a channel calls itself in a log line about its room.
const KIND: &str = "channel";
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

pub(crate) mod types;
pub use types::*;
struct ChannelSession {
    pub(super) name: String,
    pub(super) topic: String,
    pub(super) blob_topic: String,
    pub(super) mesh_id: String,
    pub(super) display_name: String,
    pub(super) device_fingerprint: String,
    pub(super) listen_port: u16,
    pub(super) static_peer: Option<String>,
    pub(super) node: Arc<MossNode>,
    pub(super) messages: MessageLog<ChannelMessage>,
    pub(super) seen: SeenFrames,
    pub(super) transfer: Transfer,
    pub(super) outbound_attempts: HashMap<String, OutboundAttemptRecord>,
    pub(super) dm_offers: DmOffers,
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
        // Claim the channel topics before any node of ours can start; see
        // `crate::inbox`.
        channel_inbox();
        Self {
            shared_node,
            channels: ConversationRuntime::new(attachment_store, persistence, CHANNEL_HISTORY),
        }
    }

    /// Reaching for one open channel, the way every facade method starts.
    /// Takes the already-normalized name.
    fn channel_mut(
        &mut self,
        normalized: &str,
    ) -> Result<&mut ChannelSession, ChannelRuntimeError> {
        self.channels
            .get_mut(normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.to_string()))
    }

    /// The read-only reach, for snapshot builds that must not touch state.
    fn channel_ref(&self, normalized: &str) -> Result<&ChannelSession, ChannelRuntimeError> {
        self.channels
            .get(normalized)
            .ok_or_else(|| ChannelRuntimeError::MissingChannel(normalized.to_string()))
    }

    /// Take a reference to the shared node and put this channel's room on it.
    fn open_channel_room(
        &mut self,
        mesh_id: &str,
        topic: &str,
        blob_topic: &str,
        listen_port: u16,
        static_peer: Option<String>,
    ) -> Result<Arc<MossNode>, ChannelRuntimeError> {
        runtime::open_room(
            &self.shared_node,
            mesh_id,
            &[topic.to_string(), blob_topic.to_string()],
            listen_port,
            static_peer,
        )
        .map_err(ChannelRuntimeError::Moss)
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
            let session = self.channel_mut(&normalized)?;
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
        self.channels.persist_tail();
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
            let session = self.channel_mut(&normalized)?;
            let prepared = session.outbox().reopen(message_id)?;
            (session.name.clone(), session.topic.clone(), prepared)
        };
        let result = self.publish_prepared(&normalized, &topic, channel_name, prepared)?;
        self.channels.persist_tail();
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
        self.channels
            .persist_send(normalized, &prepared.message_id, false);
        let publish = {
            let session = self.channel_ref(normalized)?;
            session
                .node
                .publish_room(&session.mesh_id, topic, &prepared.payload)
                .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))
        };
        let settled = {
            let session = self.channel_mut(normalized)?;
            session.outbox().settle(
                &prepared.message_id,
                publish.map_err(|error| error.to_string()),
                OnSent::Forget,
            )?
        };
        self.channels
            .persist_send(normalized, &prepared.message_id, false);
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
        let session = self.channel_mut(&normalized)?;
        let result = session.send_attachment(file_name, mime, bytes, thumbnail, voice)?;
        self.channels.persist_tail();
        Ok(result)
    }

    pub fn download_attachment(
        &mut self,
        name: &str,
        attachment_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        self.drain_inbound()?;
        let normalized = normalize_name(name)?;
        let session = self.channel_mut(&normalized)?;
        session.transfer.start_download(attachment_id)?;
        session.pump_attachment_requests();
        Ok(())
    }

    pub fn cancel_attachment(
        &mut self,
        name: &str,
        attachment_id: &str,
    ) -> Result<(), ChannelRuntimeError> {
        let normalized = normalize_name(name)?;
        let session = self.channel_mut(&normalized)?;
        Ok(session.transfer.cancel(attachment_id)?)
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
        let session = self.channel_mut(&normalized)?;
        let outcome = session.transfer.stream_range(attachment_id, start, end);
        session.pump_attachment_requests();
        Ok(outcome)
    }

    pub fn poll(&mut self, name: &str) -> Result<ChannelSnapshot, ChannelRuntimeError> {
        self.drain_inbound()?;
        self.channels.persist_tail();
        let normalized = normalize_name(name)?;
        Ok(self.channel_ref(&normalized)?.snapshot())
    }

    pub fn list(&mut self) -> Result<ChannelListSnapshot, ChannelRuntimeError> {
        self.drain_inbound()?;
        self.channels.persist_tail();
        let mut channels: Vec<ChannelSnapshot> = self
            .channels
            .values()
            .map(ChannelSession::snapshot)
            .collect();
        channels.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(ChannelListSnapshot { channels })
    }

    pub fn drain_inbound(&mut self) -> Result<(), ChannelRuntimeError> {
        let inbound = channel_inbox().drain();
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
}

impl ConversationSession for ChannelSession {
    type Message = ChannelMessage;
    type Record = PersistedChannelSession;

    fn conversation_id(&self) -> &str {
        &self.name
    }

    fn log(&self) -> &MessageLog<ChannelMessage> {
        &self.messages
    }

    fn attempts(&self) -> &HashMap<String, OutboundAttemptRecord> {
        &self.outbound_attempts
    }

    fn record(&self) -> PersistedChannelSession {
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
}

// The session's own machinery: message handling and the blob topic.
// Both are `impl ChannelSession` on the same struct.
mod blob;
mod lifecycle;
mod session;

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

/// The public channel's own inbound queue, claimed once for the process.
fn channel_inbox() -> &'static inbox::Inbox {
    static INBOX: std::sync::OnceLock<inbox::Inbox> = std::sync::OnceLock::new();
    INBOX.get_or_init(|| {
        inbox::register(|channel| {
            channel_name_from_topic(channel).is_some() || channel_name_from_blob(channel).is_some()
        })
    })
}

/// Always room-scoped: the shared node's own room is the substrate, so a
/// room-less publish would land where none of this channel's peers listen.
///
/// Best-effort: this carries presence and blob frames, which repeat on their
/// own and report no delivery status, so an empty channel is not a failure to
/// hand back. A user message does not come through here — it publishes
/// directly in `publish_prepared`, where "no peers" does fail the send.
fn publish_json<T: Serialize>(
    node: &MossNode,
    mesh_id: &str,
    topic: &str,
    value: &T,
) -> Result<(), ChannelRuntimeError> {
    let payload =
        serde_json::to_vec(value).map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
    node.publish_room_best_effort(mesh_id, topic, &payload)
        .map_err(|error| ChannelRuntimeError::Moss(error.to_string()))
}

#[cfg(test)]
#[cfg(test)]
#[path = "channel_runtime/runtime_tests.rs"]
mod tests;
