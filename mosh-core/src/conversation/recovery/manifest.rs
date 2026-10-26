use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct HistoryKey {
    pub message_id: String,
    pub sent_at_ms: u64,
    pub digest: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct Manifest {
    pub digest: String,
    pub total: usize,
}

pub(crate) fn digest(value: &impl Serialize) -> Result<String, String> {
    use sha2::{Digest, Sha256};
    Ok(hex::encode(Sha256::digest(
        serde_json::to_vec(value).map_err(|e| e.to_string())?,
    )))
}

/// Local row locator stays outside the advertised semantic manifest.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FrozenKey {
    pub key: HistoryKey,
    pub row_key: String,
}

pub(crate) fn canonical_hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}
