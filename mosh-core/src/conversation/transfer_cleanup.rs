use super::*;
use crate::persistence::Persistence;

impl Transfer {
    pub(crate) fn collect_erased_cache(&mut self, store: &Persistence) {
        let Ok(records) = store.attachment_gc(self.gc_after.as_deref()) else {
            return;
        };
        if records.is_empty() {
            self.gc_after = None;
        }
        for (key, attachment) in records {
            self.gc_after = Some(key.clone());
            if self.clean_erased(&attachment, Some(store)).unwrap_or(false) {
                let _ = store.complete_attachment_gc(&key);
            }
        }
    }
    pub(super) fn retain_lease(
        &mut self,
        descriptor: &AttachmentDescriptor,
    ) -> Result<(), TransferError> {
        if !self.leases.contains_key(&descriptor.attachment_id) {
            self.store
                .retain(&descriptor.content_hash, &descriptor.file_name)?;
            self.leases.insert(
                descriptor.attachment_id.clone(),
                (
                    descriptor.content_hash.clone(),
                    descriptor.file_name.clone(),
                ),
            );
        }
        Ok(())
    }

    pub(super) fn release_lease(&mut self, id: &str) {
        if let Some((hash, name)) = self.leases.remove(id) {
            self.store.release(&hash, &name);
        }
    }

    pub(crate) fn clean_erased(
        &self,
        attachment: &AttachmentDescriptor,
        store: Option<&Persistence>,
    ) -> Result<bool, String> {
        self.store
            .remove_if_unused(&attachment.content_hash, &attachment.file_name, || {
                store.map_or(Ok(false), |store| {
                    store
                        .attachment_referenced(&attachment.content_hash, &attachment.file_name)
                        .map_err(|e| e.to_string())
                })
            })
    }
}

impl Drop for Transfer {
    fn drop(&mut self) {
        for (hash, name) in self.leases.values() {
            self.store.release(hash, name);
        }
    }
}
