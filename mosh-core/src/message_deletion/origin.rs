use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::mls_crypto::MlsSessionCrypto;

const CONTEXT: &[u8] = b"mosh-message-origin-v1\0";

/// A portable proof names one original send, including its conversation and
/// content digest. MLS receivers additionally match this key to the actual leaf.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageOrigin {
    pub conversation: String,
    pub id: String,
    pub content_hash: String,
    pub author: String,
    pub signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ownership: Option<String>,
}

impl MessageOrigin {
    pub(crate) fn verify_from_signer(
        &self,
        conversation: &str,
        id: &str,
        content: &[u8],
        signer: &[u8],
    ) -> Result<(), String> {
        self.verify(conversation, id, content)?;
        if self.author != hex::encode(signer) {
            return Err("message origin signer mismatch".into());
        }
        Ok(())
    }

    pub(crate) fn verify_manifest_from_signer(
        &self,
        conversation: &str,
        manifest: &crate::attachment_runtime::AttachmentManifest,
        signer: &[u8],
    ) -> Result<(), String> {
        self.verify_from_signer(
            conversation,
            &manifest.attachment_id,
            &Self::manifest_bytes(manifest)?,
            signer,
        )
    }
    pub(crate) fn manifest_bytes(
        manifest: &crate::attachment_runtime::AttachmentManifest,
    ) -> Result<Vec<u8>, String> {
        let mut manifest = manifest.clone();
        manifest.origin = None;
        serde_json::to_vec(&manifest).map_err(|e| e.to_string())
    }

    pub(crate) fn verify_manifest(
        &self,
        conversation: &str,
        manifest: &crate::attachment_runtime::AttachmentManifest,
    ) -> Result<(), String> {
        self.verify(
            conversation,
            &manifest.attachment_id,
            &Self::manifest_bytes(manifest)?,
        )
    }
    pub(crate) fn sign(
        conversation: &str,
        id: &str,
        content: &[u8],
        key: &SigningKey,
        store: Option<&std::sync::Arc<crate::persistence::Persistence>>,
    ) -> Result<Self, String> {
        let mut origin = Self::unsigned(conversation, id, content, key.verifying_key().as_bytes());
        let peer = hex::encode(key.verifying_key().as_bytes());
        origin.ownership = super::ownership::create(store, Some(&peer), &origin.author)
            .map_err(|e| e.to_string())?;
        origin.signature = hex::encode(key.sign(&origin.signing_input()?).to_bytes());
        Ok(origin)
    }

    pub(crate) fn sign_mls(
        conversation: &str,
        id: &str,
        content: &[u8],
        crypto: &MlsSessionCrypto,
        store: Option<&std::sync::Arc<crate::persistence::Persistence>>,
        peer: Option<&str>,
    ) -> Result<Self, String> {
        let mut origin = Self::unsigned(conversation, id, content, &crypto.signer_public());
        origin.ownership =
            super::ownership::create(store, peer, &origin.author).map_err(|e| e.to_string())?;
        origin.signature = hex::encode(
            crypto
                .sign_sender_proof(&origin.signing_input()?)
                .map_err(|e| e.to_string())?,
        );
        Ok(origin)
    }

    fn unsigned(conversation: &str, id: &str, content: &[u8], key: &[u8]) -> Self {
        Self {
            conversation: conversation.into(),
            id: id.into(),
            content_hash: hex::encode(Sha256::digest(content)),
            author: hex::encode(key),
            signature: String::new(),
            ownership: None,
        }
    }

    pub fn verify(&self, conversation: &str, id: &str, content: &[u8]) -> Result<(), String> {
        if self.conversation != conversation
            || self.id != id
            || self.content_hash != hex::encode(Sha256::digest(content))
        {
            return Err("message origin mismatch".into());
        }
        self.verify_signature()
    }

    pub(crate) fn verify_signature(&self) -> Result<(), String> {
        if let Some(proof) = &self.ownership {
            super::ownership::verify(proof, &self.author)?;
        }
        if self.conversation.is_empty()
            || self.conversation.len() > 512
            || self.id.is_empty()
            || self.id.len() > 256
            || self.content_hash.len() != 64
        {
            return Err("invalid message origin".into());
        }
        verify_signature(&self.author, &self.signature, &self.signing_input()?)
    }

    pub(crate) fn key(&self) -> Result<String, String> {
        Ok(hex::encode(Sha256::digest(self.signing_input()?)))
    }

    fn signing_input(&self) -> Result<Vec<u8>, String> {
        let mut bytes = CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.conversation,
                &self.id,
                &self.content_hash,
                &self.author,
                &self.ownership,
            ))
            .map_err(|e| e.to_string())?,
        );
        Ok(bytes)
    }
}

pub(crate) fn verify_signature(key: &str, signature: &str, input: &[u8]) -> Result<(), String> {
    let bytes: [u8; 32] = hex::decode(key)
        .map_err(|e| e.to_string())?
        .try_into()
        .map_err(|_| "invalid signing key")?;
    let key = VerifyingKey::from_bytes(&bytes).map_err(|e| e.to_string())?;
    if key.is_weak() {
        return Err("weak signing key".into());
    }
    let signature = hex::decode(signature).map_err(|e| e.to_string())?;
    let signature = Signature::from_slice(&signature).map_err(|e| e.to_string())?;
    key.verify_strict(input, &signature)
        .map_err(|e| e.to_string())
}
