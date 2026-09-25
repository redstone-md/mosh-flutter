//! The blob channel: chunk requests, chunk serving, and manifests.

use super::*;
use crate::stream_transport::Carrier;

impl PrivateDmSession {
    pub(super) fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
        let envelope: BlobEnvelope = decode_json(&payload)?;
        match envelope {
            BlobEnvelope::Request {
                participant_id,
                request,
            } if participant_id != self.participant_id => {
                // One route decision per request: `reach` asks moss for the
                // whole mesh report, too dear to repeat for every chunk.
                let mut stream_peer = self.blob_stream_peer(now_ms());
                for frame in self.transfer.serve(&request) {
                    let chunk = BlobEnvelope::Chunk {
                        participant_id: self.participant_id.clone(),
                        frame,
                    };
                    let bytes = serde_json::to_vec(&chunk)
                        .map_err(|error| PrivateDmRuntimeError::Codec(error.to_string()))?;
                    let carrier = self.route_blob_frame(stream_peer.as_deref(), &bytes)?;
                    if stream_peer.is_some() && carrier == Carrier::Room {
                        self.stream_backoff_until_ms = now_ms() + STREAM_BACKOFF_MS;
                        stream_peer = None;
                    }
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

    /// The peer to stream chunks to, or `None` for the room wire. Only a
    /// direct peer: moss relays a relayed peer's stream send through a relay
    /// round trip (up to 5 s), and opens an unknown peer's stream with a
    /// route lookup (up to 20 s), both while this runtime is locked. A
    /// stream that just failed is left alone for the backoff window.
    fn blob_stream_peer(&self, now_ms: u64) -> Option<String> {
        if now_ms < self.stream_backoff_until_ms || self.reach() != PeerTransport::Direct {
            return None;
        }
        self.peer_moss_id.clone()
    }

    /// The blob carrier (spec #8): a chunk rides the moss stream to
    /// `stream_peer` when there is one, and the room wire otherwise —
    /// including the "no peers yet" refusals the room path already tolerates.
    /// Requests stay room-bound either way: they are small, they repeat on
    /// their own cadence, and a stream request would race the room fallback
    /// for ordering. Error surfacing matches `route_send` on the Blob kind:
    /// "no peers" is not news.
    pub(super) fn route_blob_frame(
        &self,
        stream_peer: Option<&str>,
        bytes: &[u8],
    ) -> Result<Carrier, PrivateDmRuntimeError> {
        let transport = Arc::clone(&self.transport);
        let stream = stream_peer.map(|peer| (&*transport as &dyn DmTransport, peer));
        crate::stream_transport::send_chunk(
            stream,
            |payload| match transport.publish(&self.mesh_id, &self.blob_channel, payload) {
                Ok(()) => Ok(()),
                Err(PublishError::NoPeers(_)) => Ok(()),
                Err(error) => Err(error.to_string()),
            },
            &self.blob_channel,
            bytes,
        )
        .map_err(PrivateDmRuntimeError::Moss)
    }

    pub(super) fn accept_incoming_manifest(
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
            read: None,
        });
        self.messages.push(message);
        Ok(())
    }

    pub(super) fn send_attachment(
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
            read: None,
        });
        self.messages.push(message);
        Ok(AttachmentSendResult {
            conversation_id: self.session_id.clone(),
            attachment_id,
            content_hash,
        })
    }

    pub(super) fn pump_attachment_requests(&mut self) {
        for request in self.transfer.next_requests() {
            let envelope = BlobEnvelope::Request {
                participant_id: self.participant_id.clone(),
                request,
            };
            if let Ok(bytes) = serde_json::to_vec(&envelope) {
                // Requests ride the room wire, not the stream (spec #8):
                // they are small, repeat on their own cadence, and the retry
                // bookkeeping keys on them; only the CHUNK frames the
                // request provokes take the stream fast path in handle_blob.
                let _ = self.route_send(ChannelKind::Blob, &bytes);
            }
        }
    }

    /// A frame for this session from the other participant. Our own frames
    /// come back on the shared node and are not news.
    pub(super) fn is_from_counterpart(&self, session_id: &str, participant_id: &str) -> bool {
        self.session_id == session_id && self.participant_id != participant_id
    }

    pub(super) fn is_alice_session(&self, session_id: &str, participant_id: &str) -> bool {
        matches!(self.role, SessionRole::Alice)
            && self.session_id == session_id
            && self.participant_id != participant_id
    }

    pub(super) fn is_bob_session(&self, session_id: &str, participant_id: &str) -> bool {
        matches!(self.role, SessionRole::Bob)
            && self.session_id == session_id
            && self.participant_id != participant_id
    }
}
