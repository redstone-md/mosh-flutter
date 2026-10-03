//! Playback range reads prioritize missing chunks without changing download policy.
use super::*;

impl AttachmentRuntime {
    pub fn stream_range(&mut self, attachment_id: &str, start: u64, end: u64) -> StreamRange {
        let Some(transfer) = self.incoming.get_mut(attachment_id) else {
            return StreamRange::Unknown;
        };
        transfer.download_started = true;
        let total = transfer.manifest.total_size;
        let mime = transfer.manifest.mime.clone();
        if total == 0 || start >= total {
            return StreamRange::Ready {
                bytes: Vec::new(),
                total_size: total,
                mime,
            };
        }
        let end = end.min(total).max(start);
        let chunk = u64::from(transfer.manifest.chunk_size);
        let first = start / chunk;
        let last = if end > start {
            (end - 1) / chunk
        } else {
            first
        };

        if let Some(index) = (first..=last).find(|index| !transfer.chunks.contains_key(index)) {
            transfer.priority_chunk = Some(index);
            return StreamRange::Pending { total_size: total };
        }

        let mut assembled = Vec::new();
        for index in first..=last {
            assembled.extend_from_slice(&transfer.chunks[&index]);
        }
        let offset = (start - first * chunk) as usize;
        let span = (end - start) as usize;
        let slice = assembled
            .get(offset..(offset + span).min(assembled.len()))
            .unwrap_or(&[])
            .to_vec();
        StreamRange::Ready {
            bytes: slice,
            total_size: total,
            mime,
        }
    }
}
