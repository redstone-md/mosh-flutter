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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub production: Option<ProductionProof>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductionProof {
    pub counter: u64,
    pub writer: String,
    pub visible: bool,
    pub certificates: Vec<Certificate>,
}

impl PlusFrame {
    pub(super) fn input(&self) -> Result<Vec<u8>, String> {
        if let Some(proof) = &self.production {
            let mut bytes = b"mosh-plus-advertisement-v2\0".to_vec();
            bytes.extend(
                serde_json::to_vec(&(&self.context, &self.author, &self.ownership, proof))
                    .map_err(|_| "invalid PLUS advertisement")?,
            );
            return Ok(bytes);
        }
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
            || self
                .production
                .as_ref()
                .is_some_and(|proof| proof.counter != self.revision || self.certificate.is_some())
        {
            return Err("PLUS advertisement identity/context mismatch".into());
        }
        crate::message_deletion::origin::verify_signature(author, &self.signature, &self.input()?)?;
        crate::message_deletion::ownership::verify(&self.ownership, author)
    }
}
