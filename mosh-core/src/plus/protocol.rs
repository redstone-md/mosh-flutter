use super::Certificate;
use serde::{Deserialize, Serialize};

/// Account ownership is countersigned by the actual conversation author.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlusFrame {
    pub context: String,
    pub author: String,
    pub ownership: String,
    pub revision: u64,
    pub certificate: Option<Certificate>,
    pub signature: String,
}

impl PlusFrame {
    pub(super) fn input(&self) -> Result<Vec<u8>, String> {
        let mut bytes = b"mosh-plus-advertisement-v1\0".to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.context,
                &self.author,
                &self.ownership,
                self.revision,
                &self.certificate,
            ))
            .map_err(|_| "invalid PLUS advertisement")?,
        );
        Ok(bytes)
    }

    pub(super) fn verify(&self, context: &str, author: &str) -> Result<String, String> {
        if self.context != context
            || self.author != author
            || self.ownership.len() > 16_000
            || self.revision == 0
        {
            return Err("PLUS advertisement identity/context mismatch".into());
        }
        crate::message_deletion::origin::verify_signature(author, &self.signature, &self.input()?)?;
        crate::message_deletion::ownership::verify(&self.ownership, author)
    }
}
