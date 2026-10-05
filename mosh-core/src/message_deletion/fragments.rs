use super::{
    fragment_buffer::{split_bytes, CHUNK},
    protocol::DeletionMessage,
    DeletionBook,
};

/// Bound plaintext before the MLS/base64/sender-proof/org wrappers expand it.
pub(crate) fn split(message: &DeletionMessage) -> Result<Vec<DeletionMessage>, String> {
    let bytes = serde_json::to_vec(message).map_err(|e| e.to_string())?;
    if bytes.len() <= CHUNK {
        return Ok(vec![message.clone()]);
    }
    Ok(split_bytes(&bytes)?
        .into_iter()
        .map(DeletionMessage::Fragment)
        .collect())
}

impl DeletionBook {
    pub(super) fn assemble(
        &mut self,
        carrier: &str,
        message: DeletionMessage,
    ) -> Result<Option<DeletionMessage>, String> {
        let DeletionMessage::Fragment(fragment) = message else {
            return Ok(Some(message));
        };
        let Some(bytes) = self.fragments.add(carrier, fragment)? else {
            return Ok(None);
        };
        let message = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
        if matches!(message, DeletionMessage::Fragment(_)) {
            return Err("nested deletion fragments".into());
        }
        Ok(Some(message))
    }
}
