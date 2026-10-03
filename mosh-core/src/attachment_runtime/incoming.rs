//! Manual download registration and authenticated chunk ingestion.
use super::*;

impl AttachmentRuntime {
    pub fn register_incoming(
        &mut self,
        manifest: AttachmentManifest,
    ) -> Result<(), AttachmentRuntimeError> {
        if self.incoming.contains_key(&manifest.attachment_id) {
            return Err(AttachmentRuntimeError::DuplicateTransfer(
                manifest.attachment_id,
            ));
        }
        let (key, nonce_prefix) = manifest_keys(&manifest)?;
        if manifest.chunk_size == 0 || manifest.total_size > MAX_ATTACHMENT_SIZE {
            return Err(AttachmentRuntimeError::ManifestMismatch(
                "size or chunk_size".to_string(),
            ));
        }
        let expected_count = manifest.total_size.div_ceil(u64::from(manifest.chunk_size));
        if expected_count != manifest.chunk_count {
            return Err(AttachmentRuntimeError::ManifestMismatch(
                "chunk_count".to_string(),
            ));
        }
        self.incoming.insert(
            manifest.attachment_id.clone(),
            IncomingTransfer {
                manifest,
                key,
                nonce_prefix,
                chunks: BTreeMap::new(),
                state: TransferState::Active,
                download_started: false,
                request_cursor: 0,
                requested_at: HashMap::new(),
                priority_chunk: None,
            },
        );
        Ok(())
    }

    pub fn start_download(&mut self, attachment_id: &str) -> Result<(), AttachmentRuntimeError> {
        let transfer = self
            .incoming
            .get_mut(attachment_id)
            .ok_or_else(|| AttachmentRuntimeError::UnknownTransfer(attachment_id.to_string()))?;
        transfer.download_started = true;
        Ok(())
    }

    pub fn ingest_chunk(
        &mut self,
        frame: &ChunkFrame,
    ) -> Result<ChunkOutcome, AttachmentRuntimeError> {
        let Some(transfer) = self.incoming.get_mut(&frame.attachment_id) else {
            return Ok(ChunkOutcome::Unknown);
        };
        if transfer.state != TransferState::Active {
            return Ok(ChunkOutcome::Duplicate);
        }
        if frame.chunk_index >= transfer.manifest.chunk_count {
            return Ok(ChunkOutcome::Unknown);
        }
        if transfer.chunks.contains_key(&frame.chunk_index) {
            return Ok(ChunkOutcome::Duplicate);
        }
        let ciphertext = decode(&frame.ciphertext_b64)
            .ok_or_else(|| AttachmentRuntimeError::Codec("chunk base64".to_string()))?;
        let plaintext = decrypt_chunk(
            &transfer.key,
            &transfer.nonce_prefix,
            frame.chunk_index,
            &ciphertext,
        )?;
        transfer.chunks.insert(frame.chunk_index, plaintext);

        if transfer.chunks.len() as u64 != transfer.manifest.chunk_count {
            return Ok(ChunkOutcome::Progress(progress_of(
                &transfer.manifest,
                transfer.chunks.len() as u64,
                TransferState::Active,
            )));
        }

        transfer.complete(&frame.attachment_id)
    }
}

impl IncomingTransfer {
    fn complete(&mut self, attachment_id: &str) -> Result<ChunkOutcome, AttachmentRuntimeError> {
        let mut assembled = Vec::with_capacity(self.manifest.total_size as usize);
        for chunk in self.chunks.values() {
            assembled.extend_from_slice(chunk);
        }
        let actual_hash = sha256_hex(&assembled);
        if actual_hash != self.manifest.content_hash {
            self.state = TransferState::Failed;
            return Err(AttachmentRuntimeError::ManifestMismatch(format!(
                "content hash {actual_hash} != {}",
                self.manifest.content_hash
            )));
        }
        self.state = TransferState::Complete;
        Ok(ChunkOutcome::Complete {
            attachment_id: attachment_id.to_string(),
            content_hash: actual_hash,
            bytes: assembled,
        })
    }
}
