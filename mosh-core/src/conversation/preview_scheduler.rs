//! Bound automatic preview traffic while preserving voice and original downloads.

use super::*;
use crate::conversation::attachments::AttachmentState;

const MAX_ACTIVE_PREVIEWS: usize = 4;
const PREVIEW_RETRY_DELAY: std::time::Duration = std::time::Duration::from_secs(5);

impl Transfer {
    pub(in crate::conversation) fn request_priority(&self, id: &str) -> u8 {
        if self
            .runtime
            .manifest_of(id)
            .is_some_and(|manifest| manifest.voice.is_some())
        {
            0
        } else if self.is_preview(id) {
            1
        } else {
            2
        }
    }

    pub(in crate::conversation) fn schedule_previews(&mut self, now: Instant) {
        let active = self
            .slots
            .views(&self.runtime)
            .iter()
            .filter(|view| {
                self.is_preview(&view.attachment_id) && view.state == AttachmentState::Downloading
            })
            .count();
        let mut available = MAX_ACTIVE_PREVIEWS.saturating_sub(active);
        let waiting = self.pending_previews.len();
        for _ in 0..waiting {
            let Some(id) = self.pending_previews.pop_front() else {
                break;
            };
            if !self.is_preview(&id) {
                continue;
            }
            if available == 0
                || self
                    .preview_retry_after
                    .get(&id)
                    .is_some_and(|time| *time > now)
            {
                self.pending_previews.push_back(id);
                continue;
            }
            if self.start_download(&id).is_ok() {
                self.preview_retry_after.remove(&id);
                available -= 1;
            }
        }
    }

    pub(in crate::conversation) fn retry_preview(&mut self, id: &str) {
        if self.is_preview(id) && !self.preview_retry_after.contains_key(id) {
            if let Some(manifest) = self.runtime.manifest_of(id) {
                self.runtime.forget(id);
                let _ = self.runtime.register_incoming(manifest);
            }
            self.preview_retry_after
                .insert(id.into(), Instant::now() + PREVIEW_RETRY_DELAY);
            self.pending_previews.push_back(id.into());
        }
    }
}
