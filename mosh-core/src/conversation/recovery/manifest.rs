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

/// Streaming equivalent of hashing `(1, conversation, ordered HistoryKeys)`.
pub(crate) struct ManifestHash {
    hash: sha2::Sha256,
    total: usize,
}

impl ManifestHash {
    pub(crate) fn new(conversation: &str) -> Result<Self, String> {
        use sha2::{Digest, Sha256};
        let mut hash = Sha256::new();
        hash.update(b"[1,");
        hash.update(serde_json::to_vec(conversation).map_err(|e| e.to_string())?);
        hash.update(b",[");
        Ok(Self { hash, total: 0 })
    }

    pub(crate) fn push(&mut self, key: &HistoryKey) -> Result<usize, String> {
        use sha2::Digest;
        let index = self.total;
        if self.total != 0 {
            self.hash.update(b",");
        }
        self.hash
            .update(serde_json::to_vec(key).map_err(|e| e.to_string())?);
        self.total = self
            .total
            .checked_add(1)
            .ok_or("history manifest count overflow")?;
        Ok(index)
    }

    pub(crate) fn finish(mut self) -> Manifest {
        use sha2::Digest;
        self.hash.update(b"]]");
        Manifest {
            digest: hex::encode(self.hash.finalize()),
            total: self.total,
        }
    }
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
