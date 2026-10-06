//! The blob topic: manifests, chunk requests, chunks, and the snapshot.

use super::*;

impl ChannelSession {
    pub(super) fn handle_blob(&mut self, payload: Vec<u8>) -> Result<(), ChannelRuntimeError> {
        let envelope: ChannelBlobEnvelope = serde_json::from_slice(&payload)
            .map_err(|error| ChannelRuntimeError::Codec(error.to_string()))?;
        match envelope {
            ChannelBlobEnvelope::MessageDeletion { frame } => self.receive_deletion_frame(frame),
            ChannelBlobEnvelope::Manifest {
                from_device,
                from_fingerprint,
                manifest,
            } if from_fingerprint != self.device_fingerprint => {
                self.accept_incoming_manifest(from_device, from_fingerprint, *manifest)
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
        manifest: impl Into<AttachmentOffer>,
    ) -> Result<(), ChannelRuntimeError> {
        let offer = manifest.into();
        offer
            .verify(&format!("channel:{}", self.name), None)
            .map_err(ChannelRuntimeError::Codec)?;
        let manifest = &offer.manifest;
        let origin = manifest.origin.clone();
        if let Some(origin) = &origin {
            if origin.author != from_fingerprint.to_lowercase() {
                return Err(ChannelRuntimeError::Codec(
                    "channel attachment signer mismatch".into(),
                ));
            }
        }
        let message_id = origin.as_ref().map(|o| o.id.clone());
        let Some(descriptor) = self.transfer.accept_offer(offer)? else {
            return Ok(());
        };
        let message = self.messages.stamp(ChannelMessage {
            metadata: origin.map(|origin| crate::message_deletion::MessageMetadata {
                origin: Some(origin),
                ..Default::default()
            }),
            from_device,
            from_fingerprint,
            body: String::new(),
            message_id,
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
        input: AttachmentInput,
    ) -> Result<AttachmentSendResult, ChannelRuntimeError> {
        let AttachmentInput {
            file_name,
            mime,
            bytes,
            thumbnail,
            preview,
            voice,
        } = input;
        let attachment_id = crate::message_id::occurrence_id("attachment");
        let mut outgoing = self.transfer.prepare_offer(
            OutgoingAttachment {
                attachment_id: attachment_id.clone(),
                file_name,
                mime,
                from_fingerprint: self.device_fingerprint.clone(),
                bytes,
                thumbnail_b64: thumbnail,
                voice,
            },
            preview,
        )?;
        let content_hash = outgoing.manifest.content_hash.clone();
        let publication = (|| -> Result<_, ChannelRuntimeError> {
            let origin = outgoing
                .sign(
                    &format!("channel:{}", self.name),
                    self.node
                        .identity_signer()
                        .map_err(|e| ChannelRuntimeError::Moss(e.to_string()))?,
                    self.deletions.store.as_ref(),
                )
                .map_err(ChannelRuntimeError::Codec)?;
            let envelope = ChannelBlobEnvelope::Manifest {
                from_device: self.display_name.clone(),
                from_fingerprint: self.device_fingerprint.clone(),
                manifest: Box::new(outgoing.offer()),
            };
            publish_json(&self.node, &self.mesh_id, &self.blob_topic, &envelope)?;
            Ok(origin)
        })();
        let (descriptor, origin) = self.transfer.record_published(outgoing, publication)?;
        let message = self.messages.stamp(ChannelMessage {
            metadata: Some(crate::message_deletion::MessageMetadata {
                origin: Some(origin),
                is_own: Some(true),
                ..Default::default()
            }),
            from_device: self.display_name.clone(),
            from_fingerprint: self.device_fingerprint.clone(),
            body: String::new(),
            message_id: Some(attachment_id.clone()),
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
        let authority = self.deletion_authority().ok();
        ChannelSnapshot {
            deletion_summary: self.deletions.summary(),
            name: self.name.clone(),
            topic: self.topic.clone(),
            mesh_id: self.mesh_id.clone(),
            display_name: self.display_name.clone(),
            device_fingerprint: self.device_fingerprint.clone(),
            messages: crate::message_deletion::snapshot::messages(
                &self.messages,
                &self.transfer,
                &self.deletions,
                authority.as_ref(),
            ),
            attachments: self.transfer.views(),
            dm_offers: self.dm_offers.to_vec(),
            mesh: mesh::mesh_info(&self.node),
            events: mesh::snapshot_events(),
        }
    }
}
