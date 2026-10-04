//! One bounded peer window; timed retries precede new sequential chunks.
use super::*;

impl AttachmentRuntime {
    pub fn next_chunk_request(&mut self, attachment_id: &str) -> Option<ChunkRequest> {
        self.next_chunk_request_at(attachment_id, Instant::now())
    }

    pub fn next_chunk_request_at(
        &mut self,
        attachment_id: &str,
        now: Instant,
    ) -> Option<ChunkRequest> {
        self.next_chunk_request_with_budget_at(attachment_id, now, MAX_REQUEST_BATCH)
    }

    pub(crate) fn available_request_slots_at(&self, now: Instant) -> usize {
        let in_flight = self
            .incoming
            .values()
            .filter(|transfer| transfer.download_started && transfer.state == TransferState::Active)
            .flat_map(|transfer| {
                transfer.requested_at.iter().filter(|(index, sent)| {
                    !transfer.chunks.contains_key(index)
                        && now.saturating_duration_since(**sent) < CHUNK_REQUEST_TIMEOUT
                })
            })
            .count();
        MAX_REQUEST_BATCH.saturating_sub(in_flight)
    }

    pub(crate) fn next_chunk_request_with_budget_at(
        &mut self,
        attachment_id: &str,
        now: Instant,
        budget: usize,
    ) -> Option<ChunkRequest> {
        let budget = budget.min(self.available_request_slots_at(now));
        let transfer = self.incoming.get_mut(attachment_id)?;
        if budget == 0 || !transfer.download_started || transfer.state != TransferState::Active {
            return None;
        }
        let indices =
            transfer.request_indices(now, budget.min(request_batch(transfer.manifest.chunk_size)));
        if indices.is_empty() {
            return None;
        }
        for &index in &indices {
            transfer.requested_at.insert(index, now);
        }
        Some(ChunkRequest {
            attachment_id: attachment_id.to_string(),
            chunk_indices: indices,
        })
    }

    pub fn pending_chunk_indices(
        &self,
        attachment_id: &str,
    ) -> Result<Vec<u64>, AttachmentRuntimeError> {
        let transfer = self
            .incoming
            .get(attachment_id)
            .ok_or_else(|| AttachmentRuntimeError::UnknownTransfer(attachment_id.to_string()))?;
        if transfer.state != TransferState::Active {
            return Ok(Vec::new());
        }
        Ok((0..transfer.manifest.chunk_count)
            .filter(|index| !transfer.chunks.contains_key(index))
            .take(request_batch(transfer.manifest.chunk_size))
            .collect())
    }
}

impl IncomingTransfer {
    fn wanted(&self, index: u64, now: Instant) -> bool {
        !self.chunks.contains_key(&index)
            && self
                .requested_at
                .get(&index)
                .is_none_or(|sent| now.saturating_duration_since(*sent) >= CHUNK_REQUEST_TIMEOUT)
    }

    fn request_indices(&mut self, now: Instant, batch: usize) -> Vec<u64> {
        if let Some(priority) = self.priority_chunk {
            let indices: Vec<_> = (priority..self.manifest.chunk_count)
                .filter(|&index| self.wanted(index, now))
                .take(batch)
                .collect();
            // In-flight chunks keep playback priority until they arrive.
            if (priority..self.manifest.chunk_count).all(|index| self.chunks.contains_key(&index)) {
                self.priority_chunk = None;
            }
            if !indices.is_empty() {
                return indices;
            }
        }
        let gaps: Vec<_> = (0..self.request_cursor)
            .filter(|&index| self.wanted(index, now))
            .take(batch)
            .collect();
        if !gaps.is_empty() {
            return gaps;
        }
        let end = (self.request_cursor + batch as u64).min(self.manifest.chunk_count);
        let indices = (self.request_cursor..end).collect();
        self.request_cursor = end;
        indices
    }
}
