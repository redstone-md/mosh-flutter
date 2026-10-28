//! Optional signed transfer requests retain compatibility with legacy peers.
use super::*;
use crate::message_deletion::MessageOrigin;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestExecution {
    pub token: String,
    pub phase: RequestPhase,
    pub receiver: String,
    pub expires_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proof: Option<MessageOrigin>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RequestPhase {
    Request,
    Complete,
    Ack,
}

impl ChunkRequest {
    pub(crate) fn signing_bytes(&self) -> Result<Vec<u8>, String> {
        let mut request = self.clone();
        let execution = request
            .execution
            .as_mut()
            .ok_or("missing transfer execution")?;
        execution.proof = None;
        serde_json::to_vec(&request).map_err(|error| error.to_string())
    }

    pub(crate) fn verify_execution(&self, context: &str) -> Result<Option<&str>, String> {
        let Some(execution) = &self.execution else {
            return Ok(None);
        };
        if execution.token.len() != 32
            || !execution.token.bytes().all(|b| b.is_ascii_hexdigit())
            || execution.expires_ms < crate::conversation::now_ms()
            || execution.expires_ms > crate::conversation::now_ms().saturating_add(180_000)
            || self.chunk_indices.len() > 256
            || execution.receiver.len() > 64
            || (execution.phase != RequestPhase::Request && !self.chunk_indices.is_empty())
        {
            return Err("invalid transfer request".into());
        }
        let proof = execution
            .proof
            .as_ref()
            .ok_or("unsigned transfer execution")?;
        proof.verify(context, &execution.token, &self.signing_bytes()?)?;
        if execution.phase != RequestPhase::Ack && execution.receiver != proof.author {
            return Err("transfer receiver signer mismatch".into());
        }
        Ok(Some(&proof.author))
    }

    pub(crate) fn sign_execution(
        &mut self,
        author: &str,
        sign: impl FnOnce(&str, &[u8]) -> Result<MessageOrigin, String>,
    ) -> Result<(), String> {
        if let Some(execution) = &mut self.execution {
            execution.expires_ms = crate::conversation::now_ms().saturating_add(120_000);
            if execution.phase != RequestPhase::Ack {
                execution.receiver = author.into();
            }
        }
        if let Some(token) = self.execution.as_ref().map(|value| value.token.clone()) {
            let proof = sign(&token, &self.signing_bytes()?)?;
            self.execution.as_mut().unwrap().proof = Some(proof);
        }
        Ok(())
    }
}
