use super::*;
use std::collections::BTreeSet;

impl Persistence {
    pub(crate) fn remember_deletion_admins(
        &self,
        context: &str,
        current: &BTreeSet<String>,
    ) -> Result<BTreeSet<String>, PersistenceError> {
        let bytes = self.get(DELETION_ADMINS, context)?;
        let mut known: BTreeSet<String> = bytes
            .as_ref()
            .map(|bytes| {
                serde_json::from_slice(bytes).map_err(|e| PersistenceError::Json(e.to_string()))
            })
            .transpose()?
            .unwrap_or_default();
        let changed = current.iter().any(|key| !known.contains(key));
        known.extend(current.iter().cloned());
        if changed {
            self.put(
                DELETION_ADMINS,
                context,
                &serde_json::to_vec(&known).map_err(|e| PersistenceError::Json(e.to_string()))?,
            )?;
        }
        Ok(known)
    }
}
