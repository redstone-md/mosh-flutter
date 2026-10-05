use super::*;
use crate::conversation::attachments::AttachmentDescriptor;

impl Persistence {
    pub(super) fn enqueue_attachment_gc(
        &self,
        tx: &redb::WriteTransaction,
        descriptor: &AttachmentDescriptor,
    ) -> Result<(), PersistenceError> {
        let key = format!("{}:{}", descriptor.content_hash, descriptor.file_name);
        let blob = encrypt_blob(
            &self.dek,
            &serde_json::to_vec(descriptor).map_err(|e| PersistenceError::Json(e.to_string()))?,
        )?;
        Self::update_row(tx, ATTACHMENT_GC, &key, Some(&blob))
    }

    pub(crate) fn attachment_gc(
        &self,
        after: Option<&str>,
    ) -> Result<Vec<(String, AttachmentDescriptor)>, PersistenceError> {
        self.list_rows(ATTACHMENT_GC)?
            .into_iter()
            .filter(|(key, _)| after.is_none_or(|after| key.as_str() > after))
            .take(16)
            .map(|(key, bytes)| {
                Ok((
                    key,
                    serde_json::from_slice(&bytes)
                        .map_err(|e| PersistenceError::Json(e.to_string()))?,
                ))
            })
            .collect()
    }

    pub(crate) fn complete_attachment_gc(&self, key: &str) -> Result<(), PersistenceError> {
        self.write(|tx| Self::update_row(tx, ATTACHMENT_GC, key, None))
    }
}
