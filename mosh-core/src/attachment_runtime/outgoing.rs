//! File preparation, restoration, and encrypted chunk serving.
use super::*;

impl AttachmentRuntime {
    pub fn prepare_outgoing(
        &mut self,
        request: OutgoingAttachment,
    ) -> Result<AttachmentManifest, AttachmentRuntimeError> {
        if request.bytes.is_empty() {
            return Err(AttachmentRuntimeError::Empty);
        }
        let total_size = request.bytes.len() as u64;
        if total_size > MAX_ATTACHMENT_SIZE {
            return Err(AttachmentRuntimeError::TooLarge { size: total_size });
        }
        if self.outgoing.contains_key(&request.attachment_id) {
            return Err(AttachmentRuntimeError::DuplicateTransfer(
                request.attachment_id,
            ));
        }
        let thumbnail_b64 = request
            .thumbnail_b64
            .filter(|thumb| thumb.len() <= MAX_THUMBNAIL_B64);
        let key = random_key();
        let nonce_prefix = random_nonce_prefix();
        let chunk_count = total_size.div_ceil(u64::from(CHUNK_SIZE));
        let manifest = AttachmentManifest {
            origin: None,
            attachment_id: request.attachment_id.clone(),
            content_hash: sha256_hex(&request.bytes),
            file_name: request.file_name,
            mime: request.mime,
            total_size,
            chunk_size: CHUNK_SIZE,
            chunk_count,
            key_b64: encode(&key),
            nonce_prefix_b64: encode(&nonce_prefix),
            thumbnail_b64,
            voice: request.voice,
            from_fingerprint: request.from_fingerprint,
        };
        self.outgoing.insert(
            request.attachment_id,
            OutgoingTransfer {
                manifest: manifest.clone(),
                plaintext: request.bytes,
                key,
                nonce_prefix,
                served_chunks: BTreeMap::new(),
                state: TransferState::Active,
            },
        );
        Ok(manifest)
    }

    pub fn serve_chunks(
        &mut self,
        request: &ChunkRequest,
    ) -> Result<Vec<ChunkFrame>, AttachmentRuntimeError> {
        let transfer = self
            .outgoing
            .get_mut(&request.attachment_id)
            .ok_or_else(|| {
                AttachmentRuntimeError::UnknownTransfer(request.attachment_id.clone())
            })?;
        if transfer.state != TransferState::Active {
            return Ok(Vec::new());
        }
        let mut frames = Vec::new();
        let chunk_size = transfer.manifest.chunk_size;
        for &index in request.chunk_indices.iter().take(request_batch(chunk_size)) {
            let Some(slice) = chunk_slice(&transfer.plaintext, index, chunk_size) else {
                continue;
            };
            let ciphertext = encrypt_chunk(&transfer.key, &transfer.nonce_prefix, index, slice)?;
            *transfer.served_chunks.entry(index).or_insert(0) += 1;
            frames.push(ChunkFrame {
                attachment_id: request.attachment_id.clone(),
                chunk_index: index,
                ciphertext_b64: encode(&ciphertext),
            });
        }
        // No receiver ack: keep serving until the session closes.
        Ok(frames)
    }

    pub fn restore_outgoing(
        &mut self,
        manifest: AttachmentManifest,
        bytes: Vec<u8>,
    ) -> Result<(), AttachmentRuntimeError> {
        if self.outgoing.contains_key(&manifest.attachment_id) {
            return Err(AttachmentRuntimeError::DuplicateTransfer(
                manifest.attachment_id,
            ));
        }
        if bytes.len() as u64 != manifest.total_size
            || sha256_hex(&bytes) != manifest.content_hash
            || manifest.chunk_size == 0
            || manifest.total_size.div_ceil(u64::from(manifest.chunk_size)) != manifest.chunk_count
        {
            return Err(AttachmentRuntimeError::ManifestMismatch(
                "restored outgoing file".to_string(),
            ));
        }
        let (key, nonce_prefix) = manifest_keys(&manifest)?;
        self.outgoing.insert(
            manifest.attachment_id.clone(),
            OutgoingTransfer {
                manifest,
                plaintext: bytes,
                key,
                nonce_prefix,
                served_chunks: BTreeMap::new(),
                state: TransferState::Active,
            },
        );
        Ok(())
    }
}
