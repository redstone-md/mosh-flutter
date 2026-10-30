//! Signed room history carrier; source authentication never replaces author proof.
use ed25519_dalek::{Signer, SigningKey};
use serde::{Deserialize, Serialize};

use super::manifest::canonical_hex;
use crate::conversation::{decode, encode, MAX_PUBLISH_BYTES};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct HistoryFrame {
    pub version: u8,
    pub conversation: String,
    pub mesh_id: String,
    pub channel: String,
    pub sender_key: String,
    pub recipient_key: Option<String>,
    pub request_id: String,
    pub round: u64,
    pub payload_b64: String,
    pub signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum HistoryMessage<R> {
    Probe,
    Offer {
        manifest: String,
        total: usize,
        deletion_digest: String,
    },
    Pull(HistoryPull),
    Page {
        manifest: String,
        total: usize,
        offset: usize,
        records: Vec<R>,
        fragment: Option<super::fragment::PageFragment>,
    },
    Journal {
        manifest: String,
        deletion_digest: String,
        page: crate::message_deletion::protocol::DeletionMessage,
    },
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct HistoryPull {
    pub manifest: String,
    pub offset: usize,
    pub fragment_offset: usize,
    pub deletion_digest: String,
    pub journal: bool,
    pub journal_after: Option<String>,
}

impl HistoryPull {
    /// The opening pull of a round: journal from its start, nothing imported.
    pub(crate) fn is_first(&self) -> bool {
        self.offset == 0
            && self.fragment_offset == 0
            && self.journal
            && self.journal_after.is_none()
    }
}

impl HistoryFrame {
    pub(crate) fn seal<R: Serialize>(
        &mut self,
        key: &SigningKey,
        message: &HistoryMessage<R>,
    ) -> Result<(), String> {
        self.seal_payload(key, message)
    }

    pub(crate) fn seal_payload<T: Serialize>(
        &mut self,
        key: &SigningKey,
        payload: &T,
    ) -> Result<(), String> {
        self.sender_key = hex::encode(key.verifying_key().as_bytes());
        self.payload_b64 = encode(&serde_json::to_vec(payload).map_err(|e| e.to_string())?);
        self.signature = hex::encode(key.sign(&self.input()?).to_bytes());
        if serde_json::to_vec(self).map_err(|e| e.to_string())?.len() > MAX_PUBLISH_BYTES - 128 {
            return Err("history frame exceeds publication limit".into());
        }
        Ok(())
    }

    pub(crate) fn open<R: serde::de::DeserializeOwned>(
        &self,
        context: &str,
        mesh: &str,
        channel: &str,
    ) -> Result<HistoryMessage<R>, String> {
        let message = self.open_payload(context, mesh, channel)?;
        if !matches!(message, HistoryMessage::Probe) && self.recipient_key.is_none() {
            return Err("history reply has no exact recipient".into());
        }
        Ok(message)
    }

    /// Kind adapters must separately enforce their Probe/exact-recipient rules.
    pub(crate) fn open_payload<T: serde::de::DeserializeOwned>(
        &self,
        context: &str,
        mesh: &str,
        channel: &str,
    ) -> Result<T, String> {
        if self.version != 1
            || self.conversation != context
            || self.mesh_id != mesh
            || self.channel != channel
            || self.round == 0
            || !canonical_hex(&self.request_id, 32)
            || self.payload_b64.len() > MAX_PUBLISH_BYTES
        {
            return Err("invalid history frame scope".into());
        }
        if !canonical_hex(&self.sender_key, 64)
            || !canonical_hex(&self.signature, 128)
            || self
                .recipient_key
                .as_ref()
                .is_some_and(|key| !canonical_hex(key, 64))
            || serde_json::to_vec(self).map_err(|e| e.to_string())?.len() > MAX_PUBLISH_BYTES - 128
        {
            return Err("history frame exceeds bounded carrier".into());
        }
        crate::signature_verification::verify(&self.sender_key, &self.signature, &self.input()?)?;
        serde_json::from_slice(&decode(&self.payload_b64).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())
    }

    fn input(&self) -> Result<Vec<u8>, String> {
        let mut bytes = b"mosh-conversation-history-frame-v1\0".to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                self.version,
                &self.conversation,
                &self.mesh_id,
                &self.channel,
                &self.sender_key,
                &self.recipient_key,
                &self.request_id,
                self.round,
                &self.payload_b64,
            ))
            .map_err(|e| e.to_string())?,
        );
        Ok(bytes)
    }
}
