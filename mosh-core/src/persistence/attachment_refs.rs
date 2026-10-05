use super::*;

impl Persistence {
    pub(crate) fn attachment_referenced(
        &self,
        hash: &str,
        name: &str,
    ) -> Result<bool, PersistenceError> {
        let matches = |value: &serde_json::Value| {
            value.get("content_hash").and_then(|v| v.as_str()) == Some(hash)
                && value
                    .get("file_name")
                    .and_then(|v| v.as_str())
                    .is_some_and(|stored| {
                        crate::attachment_store::sanitize_file_name(stored)
                            == crate::attachment_store::sanitize_file_name(name)
                    })
        };
        for table in [MESSAGES, GROUP_MESSAGES, CHANNEL_MESSAGES] {
            for (_, bytes) in self.list_rows(table)? {
                let row: serde_json::Value = serde_json::from_slice(&bytes)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
                if row.pointer("/message/attachment").is_some_and(&matches)
                    || row.get("preview_manifest").is_some_and(&matches)
                {
                    return Ok(true);
                }
            }
        }
        for (_, bytes) in self.list_rows(OUTBOUND_ATTEMPTS)? {
            let row: serde_json::Value = serde_json::from_slice(&bytes)
                .map_err(|e| PersistenceError::Json(e.to_string()))?;
            if let Some(message) = row.get("message_json").and_then(|v| v.as_str()) {
                let message: serde_json::Value = serde_json::from_str(message)
                    .map_err(|e| PersistenceError::Json(e.to_string()))?;
                if message.get("attachment").is_some_and(&matches) {
                    return Ok(true);
                }
            }
        }
        Ok(false)
    }
}
