use super::*;

impl AttachmentStore {
    pub(crate) fn retain(&self, hash: &str, name: &str) -> Result<(), AttachmentStoreError> {
        let path = self.path_for(hash, name)?;
        *self
            .leases
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .entry(path)
            .or_default() += 1;
        Ok(())
    }

    pub(crate) fn release(&self, hash: &str, name: &str) {
        let Ok(path) = self.path_for(hash, name) else {
            return;
        };
        let mut leases = self.leases.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(count) = leases.get_mut(&path) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                leases.remove(&path);
            }
        }
    }

    /// Only app-owned, computed paths are eligible. The lock also protects
    /// newly prepared transfers which have not reached history yet.
    pub(crate) fn remove_if_unused(
        &self,
        hash: &str,
        name: &str,
        referenced: impl FnOnce() -> Result<bool, String>,
    ) -> Result<bool, String> {
        let path = self.path_for(hash, name).map_err(|e| e.to_string())?;
        let leases = self.leases.lock().unwrap_or_else(|p| p.into_inner());
        if leases.contains_key(&path) || referenced()? {
            return Ok(false);
        }
        match fs::remove_file(&path) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(true),
            Err(error) => Err(error.to_string()),
        }
    }
}
