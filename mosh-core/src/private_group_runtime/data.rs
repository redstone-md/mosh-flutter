//! The data and blob channels: messages, manifests, chunks.

use super::*;

impl GroupSession {
    pub(super) fn handle_data(&mut self, payload: Vec<u8>) -> Result<(), PrivateGroupError> {
        let proof = decode_json(&payload)?;
        let sender = self.verify_application(&proof, &self.data_channel.clone())?;
        let envelope: DataEnvelope = decode_json(&sender.payload)?;
        if envelope.group_id != self.group_id || envelope.participant_id == self.participant_id {
            return Ok(());
        }
        self.require_author(&envelope.from_fingerprint, &sender)?;
        let context = format!("group:{}", self.group_id);
        let staged = self.crypto.stage_decrypt_checked(
            &decode(&envelope.ciphertext_b64)?,
            |body, signer| {
                if signer != sender.mls_signer {
                    return Err("group sender mismatch".into());
                }
                if let Some(origin) = &envelope.origin {
                    origin.verify_from_signer(
                        &context,
                        envelope.message_id.as_deref().unwrap_or_default(),
                        body,
                        signer,
                    )?;
                }
                Ok(())
            },
        )?;
        let author = envelope.from_fingerprint.clone();
        let message = self.received_text(envelope, &staged.body);
        self.persist_received_text(&staged, &message, &payload, &sender)?;
        self.crypto = staged.next;
        // Durable delivery contradicts the author's typing hint.
        self.clear_member_typing(&author);
        if self.messages.holds_copy_of(&message) {
            return Ok(());
        }
        self.messages.push(message);
        Ok(())
    }

    fn received_text(&self, envelope: DataEnvelope, plaintext: &[u8]) -> GroupMessage {
        self.messages.stamp(GroupMessage {
            metadata: envelope
                .origin
                .map(|origin| crate::message_deletion::MessageMetadata {
                    origin: Some(origin),
                    is_own: Some(false),
                    ..Default::default()
                }),
            from_device: envelope.from_device,
            from_fingerprint: envelope.from_fingerprint,
            body: String::from_utf8_lossy(plaintext).into_owned(),
            message_id: envelope.message_id,
            sent_at_ms: envelope.sent_at_ms,
            attachment: None,
            delivery_status: None,
            delivery_error: None,
            retryable: None,
            retry_count: None,
            name_change: None,
        })
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
            } if participant_id != self.participant_id => self.serve_blob_request(&request),
            BlobEnvelope::Chunk {
                participant_id,
                frame,
            } if participant_id != self.participant_id => Ok(self.transfer.ingest(&frame)?),
            _ => Ok(()),
        }
    }

    pub(super) fn accept_incoming_manifest(
        &mut self,
        message: GroupMessage,
        offer: AttachmentOffer,
    ) -> Result<(), PrivateGroupError> {
        if self.messages.holds_copy_of(&message) {
            return Ok(());
        }
        self.messages.push(message);
        self.transfer.accept_offer(offer)?;
        Ok(())
    }

    pub(super) fn send_attachment(
        &mut self,
        input: AttachmentInput,
    ) -> Result<AttachmentSendResult, PrivateGroupError> {
        let AttachmentInput {
            user_transfer_id,
            file_name,
            mime,
            bytes,
            thumbnail,
            preview,
            voice,
        } = input;
        if !self.joined || !self.crypto.is_ready() {
            return Err(PrivateGroupError::NotReady);
        }
        let attachment_id = self.crypto.random_token("attachment")?;
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
        self.transfer
            .bind_user_admission(user_transfer_id.as_deref(), &outgoing.manifest)?;
        let content_hash = outgoing.manifest.content_hash.clone();
        let sent_at_ms = now_ms();
        let publication = (|| -> Result<_, PrivateGroupError> {
            let origin = outgoing
                .sign_mls(
                    &format!("group:{}", self.group_id),
                    &self.crypto,
                    self.deletions.store.as_ref(),
                    Some(self.device_fingerprint.as_str()),
                )
                .map_err(PrivateGroupError::Codec)?;
            let manifest_ciphertext_b64 = self.crypto.encrypt_json(&outgoing.offer())?;
            let envelope = ControlEnvelope::AttachmentManifest {
                sent_at_ms: Some(sent_at_ms),
                group_id: self.group_id.clone(),
                participant_id: self.participant_id.clone(),
                from_device: self.display_name.clone(),
                from_fingerprint: self.device_fingerprint.clone(),
                manifest_ciphertext_b64,
            };
            let offer = outgoing.offer();
            let message = self.attachment_history_message(
                self.display_name.clone(),
                self.device_fingerprint.clone(),
                &offer,
                Some(sent_at_ms),
            );
            let proof = self.sign_application(&envelope, &self.control_channel)?;
            let sender = self.verify_application(&proof, &self.control_channel.clone())?;
            let bytes =
                serde_json::to_vec(&proof).map_err(|e| PrivateGroupError::Codec(e.to_string()))?;
            let accepted =
                self.prepare_attachment_publication(&message, offer.clone(), &sender, &bytes)?;
            self.persist_provisional_offer(&message, &offer)?;
            self.publish_control(&envelope)?;
            Ok((origin, message, accepted))
        })();
        let (_, (_, message, accepted)) = self.transfer.record_published(outgoing, publication)?;
        self.messages.push(message);
        self.publications.insert(attachment_id.clone(), accepted);
        Ok(AttachmentSendResult {
            conversation_id: self.group_id.clone(),
            attachment_id,
            content_hash,
        })
    }

    pub(super) fn pump_attachment_requests(&mut self) {
        for request in self.transfer.pending_serving_requests() {
            let _ = self.serve_blob_request(&request);
        }
        for mut request in self.transfer.next_requests() {
            if self.sign_blob_request(&mut request).is_err() {
                continue;
            }
            let envelope = BlobEnvelope::Request {
                participant_id: self.participant_id.clone(),
                request,
            };
            let _ = publish_json(&self.node, &self.mesh_id, &self.blob_channel, &envelope);
        }
    }
}

impl GroupSession {
    fn sign_blob_request(
        &self,
        request: &mut crate::attachment_runtime::ChunkRequest,
    ) -> Result<(), PrivateGroupError> {
        let context = format!("transfer:group:{}", self.group_id);
        let author = hex::encode(self.crypto.signer_public());
        request
            .sign_execution(&author, |token, bytes| {
                crate::message_deletion::MessageOrigin::sign_mls(
                    &context,
                    token,
                    bytes,
                    &self.crypto,
                    self.deletions.store.as_ref(),
                    None,
                )
            })
            .map_err(PrivateGroupError::Codec)
    }
    fn verify_blob_request(
        &mut self,
        request: &crate::attachment_runtime::ChunkRequest,
    ) -> Result<(), PrivateGroupError> {
        let context = format!("transfer:group:{}", self.group_id);
        if let Some(author) = request
            .verify_execution(&context)
            .map_err(PrivateGroupError::Codec)?
        {
            let signer = hex::decode(author)
                .map_err(|_| PrivateGroupError::Codec("invalid blob signer".into()))?;
            let member = self.crypto.member_identity_for_signer(&signer);
            if member.is_none()
                || (self.org_pubkey.is_some()
                    && !member
                        .as_deref()
                        .is_some_and(|peer| self.roster_contains(peer)))
            {
                return Err(PrivateGroupError::Codec(
                    "blob requester is not a current member".into(),
                ));
            }
        }
        Ok(())
    }
}

impl GroupSession {
    fn serve_blob_request(
        &mut self,
        request: &crate::attachment_runtime::ChunkRequest,
    ) -> Result<(), PrivateGroupError> {
        self.verify_blob_request(request)?;
        // Only the original sender holds the outgoing transfer;
        // every other member simply has nothing to serve.
        for frame in self.transfer.serve(request) {
            if !self.transfer.may_send_chunk(&frame.attachment_id) {
                break;
            }
            let chunk = BlobEnvelope::Chunk {
                participant_id: self.participant_id.clone(),
                frame: frame.clone(),
            };
            let bytes = serde_json::to_vec(&chunk)
                .map_err(|error| PrivateGroupError::Codec(error.to_string()))?;
            self.node
                .publish_room(&self.mesh_id, &self.blob_channel, &bytes)
                .map_err(|error| PrivateGroupError::Moss(error.to_string()))?;
            self.transfer.chunks_published(&[frame]);
        }
        Ok(())
    }
}
