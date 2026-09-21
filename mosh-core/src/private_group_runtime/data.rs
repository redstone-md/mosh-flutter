//! The data and blob channels: messages, manifests, chunks.

use super::*;

impl GroupSession {
    pub(super) fn handle_data(&mut self, payload: Vec<u8>) -> Result<(), PrivateGroupError> {
        let envelope: DataEnvelope = decode_json(&payload)?;
        if envelope.group_id != self.group_id || envelope.participant_id == self.participant_id {
            return Ok(());
        }
        let plaintext = self.crypto.decrypt(&decode(&envelope.ciphertext_b64)?)?;
        // A delivered message contradicts "typing": the author's hint dies at
        // once, whatever its deadline said.
        self.clear_member_typing(&envelope.from_fingerprint);
        let message = self.messages.stamp(GroupMessage {
            from_device: envelope.from_device,
            from_fingerprint: envelope.from_fingerprint,
            body: String::from_utf8_lossy(&plaintext).into_owned(),
            message_id: envelope.message_id,
            sent_at_ms: envelope.sent_at_ms,
            attachment: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
        });
        if self.messages.holds_copy_of(&message) {
            return Ok(());
        }
        self.messages.push(message);
        Ok(())
    }

    // Blob traffic stays on the room wire (spec #8, this slice): a group has
    // no single direct peer to stream to, and the stream carrier is the DM
    // fast path only. The chunk protocol below is unchanged.
    pub(super) fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), PrivateGroupError> {
        let envelope: BlobEnvelope = decode_json(&payload)?;
        match envelope {
            BlobEnvelope::Request {
                participant_id,
                request,
            } if participant_id != self.participant_id => {
                // Only the original sender holds the outgoing transfer;
                // every other member simply has nothing to serve.
                for frame in self.transfer.serve(&request) {
                    let chunk = BlobEnvelope::Chunk {
                        participant_id: self.participant_id.clone(),
                        frame,
                    };
                    publish_json(&self.node, &self.mesh_id, &self.blob_channel, &chunk)?;
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

    pub(super) fn accept_incoming_manifest(
        &mut self,
        from_device: String,
        from_fingerprint: String,
        manifest: AttachmentManifest,
    ) -> Result<(), PrivateGroupError> {
        let Some(descriptor) = self.transfer.accept_manifest(manifest)? else {
            return Ok(());
        };
        let message = self.messages.stamp(GroupMessage {
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

    pub(super) fn send_attachment(
        &mut self,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, PrivateGroupError> {
        if !self.joined || !self.crypto.is_ready() {
            return Err(PrivateGroupError::NotReady);
        }
        let attachment_id = self.crypto.random_token("attachment")?;
        let outgoing = self.transfer.prepare_outgoing(OutgoingAttachment {
            attachment_id: attachment_id.clone(),
            file_name,
            mime,
            from_fingerprint: self.device_fingerprint.clone(),
            bytes,
            thumbnail_b64: thumbnail,
            voice,
        })?;
        let content_hash = outgoing.manifest.content_hash.clone();
        let manifest_json = serde_json::to_vec(&outgoing.manifest)
            .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
        let ciphertext = self.crypto.encrypt(&manifest_json)?;
        let envelope = ControlEnvelope::AttachmentManifest {
            group_id: self.group_id.clone(),
            participant_id: self.participant_id.clone(),
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            manifest_ciphertext_b64: encode(&ciphertext),
        };
        self.publish_control(&envelope)?;

        let descriptor = self.transfer.record_sent(outgoing);
        let message = self.messages.stamp(GroupMessage {
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
            conversation_id: self.group_id.clone(),
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
            let _ = publish_json(&self.node, &self.mesh_id, &self.blob_channel, &envelope);
        }
    }
}
