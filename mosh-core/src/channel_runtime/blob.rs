//! The blob topic: manifests, chunk requests, chunks, and the snapshot.

use super::*;

impl ChannelSession {
    pub(super) fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), ChannelRuntimeError> {
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
                for frame in self.transfer.serve(&request) {
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
            } if from_fingerprint != self.device_fingerprint => Ok(self.transfer.ingest(&frame)?),
            _ => Ok(()),
        }
    }

    pub(super) fn accept_incoming_manifest(
        &mut self,
        from_device: String,
        from_fingerprint: String,
        manifest: AttachmentManifest,
    ) -> Result<(), ChannelRuntimeError> {
        let Some(descriptor) = self.transfer.accept_manifest(manifest)? else {
            return Ok(());
        };
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

    pub(super) fn send_attachment(
        &mut self,
        file_name: String,
        mime: String,
        bytes: Vec<u8>,
        thumbnail: Option<String>,
        voice: Option<VoiceMeta>,
    ) -> Result<AttachmentSendResult, ChannelRuntimeError> {
        let attachment_id = format!("attachment-{}", &sha256_hex(&bytes)[..16]);
        if self.transfer.holds(&attachment_id) {
            return Err(ChannelRuntimeError::Attachment(
                "attachment already shared on this channel".to_string(),
            ));
        }
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
        let envelope = ChannelBlobEnvelope::Manifest {
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            manifest: outgoing.manifest.clone(),
        };
        publish_json(&self.node, &self.mesh_id, &self.blob_topic, &envelope)?;

        let descriptor = self.transfer.record_sent(outgoing);
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
            conversation_id: self.name.clone(),
            attachment_id,
            content_hash,
        })
    }

    pub(super) fn pump_attachment_requests(&mut self) {
        for request in self.transfer.next_requests() {
            let envelope = ChannelBlobEnvelope::Request {
                from_fingerprint: self.device_fingerprint.clone(),
                request,
            };
            let _ = publish_json(&self.node, &self.mesh_id, &self.blob_topic, &envelope);
        }
    }

    pub(super) fn snapshot(&self) -> ChannelSnapshot {
        ChannelSnapshot {
            name: self.name.clone(),
            topic: self.topic.clone(),
            mesh_id: self.mesh_id.clone(),
            display_name: self.display_name.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            messages: self.messages.to_vec(),
            attachments: self.transfer.views(),
            dm_offers: self.dm_offers.to_vec(),
            mesh: mesh::mesh_info(&self.node),
            events: mesh::snapshot_events(),
        }
    }
}
