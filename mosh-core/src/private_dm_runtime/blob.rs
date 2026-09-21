//! The blob channel: chunk requests, chunk serving, and manifests.

use super::*;

impl PrivateDmSession {
    pub(super) fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), PrivateDmRuntimeError> {
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
                    self.route_blob_frame(&bytes)?;
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

    /// The blob carrier (spec #8): a chunk rides the moss stream when the
    /// counterpart's direct peer id is known, and falls back to the room
    /// wire otherwise — including the "no peers yet" refusals the room path
    /// already tolerates. Requests stay room-bound either way: they are
    /// small, they repeat on their own cadence, and a stream request would
    /// race the room fallback for ordering. Error surfacing matches
    /// `route_send` on the Blob kind: "no peers" is not news.
    pub(super) fn route_blob_frame(&self, bytes: &[u8]) -> Result<(), PrivateDmRuntimeError> {
        let blob_channel = self.blob_channel.clone();
        let stream_peer = self.peer_moss_id.clone();
        let mesh_id = self.mesh_id.clone();
        let transport = Arc::clone(&self.transport);
        let stream = stream_peer
            .as_deref()
            .map(|peer| (&*transport as &dyn DmTransport, peer));
        let outcome = crate::stream_transport::send_chunk(
            stream,
            |payload| match transport.publish(&mesh_id, &blob_channel, payload) {
                Ok(()) => Ok(()),
                Err(PublishError::NoPeers(_)) => Ok(()),
                Err(error) => Err(error.to_string()),
            },
            &blob_channel,
            bytes,
        );
        outcome.map_err(PrivateDmRuntimeError::Moss)
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
