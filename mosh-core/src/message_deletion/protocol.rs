use super::{origin::verify_signature, MessageOrigin};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DeleteRequest {
    pub operation: String,
    pub target: MessageOrigin,
    pub actor: String,
    pub actor_name: String,
    pub moderated: bool,
    pub epoch: u64,
    pub signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ownership: Option<String>,
}

impl DeleteRequest {
    pub fn input(&self) -> Result<Vec<u8>, String> {
        transcript(
            b"mosh-delete-request-v1\0",
            &(
                &self.operation,
                &self.target,
                &self.actor,
                &self.actor_name,
                self.moderated,
                self.epoch,
                &self.ownership,
            ),
        )
    }

    pub fn verify(&self, context: &str) -> Result<(), String> {
        super::ownership::verify(
            self.ownership
                .as_deref()
                .ok_or("deletion account is not verified")?,
            &self.actor,
        )?;
        if self.target.conversation != context
            || self.operation.len() != 39
            || self.actor_name.chars().count() > 64
            || self.actor_name.chars().any(char::is_control)
        {
            return Err("invalid deletion request".into());
        }
        self.target.verify_signature()?;
        verify_signature(&self.actor, &self.signature, &self.input()?)
    }

    pub fn digest(&self) -> Result<String, String> {
        use sha2::{Digest, Sha256};
        Ok(hex::encode(Sha256::digest(self.input()?)))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct DeleteAck {
    pub request_digest: String,
    pub actor: String,
    pub signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ownership: Option<String>,
}

impl DeleteAck {
    pub fn input(&self) -> Result<Vec<u8>, String> {
        transcript(
            b"mosh-delete-saved-v1\0",
            &(&self.request_digest, &self.actor, &self.ownership),
        )
    }

    pub fn verify(&self, request: &DeleteRequest) -> Result<(), String> {
        super::ownership::verify(
            self.ownership
                .as_deref()
                .ok_or("recipient account is not verified")?,
            &self.actor,
        )?;
        if self.request_digest != request.digest()? || self.actor == request.actor {
            return Err("invalid deletion acknowledgement".into());
        }
        if super::ownership::same_account(
            &self.actor,
            self.ownership.as_deref(),
            &request.actor,
            request.ownership.as_deref(),
        ) {
            return Err("deletion receipt must be from another account".into());
        }
        verify_signature(&self.actor, &self.signature, &self.input()?)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) enum DeletionMessage {
    Fragment(super::fragment_buffer::PageFragment),
    Request {
        after: Option<String>,
        #[serde(default)]
        digest: Option<String>,
    },
    State {
        records: Vec<super::DeletionRecord>,
        next: Option<String>,
    },
    Ack {
        key: String,
        acknowledgement: DeleteAck,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct DeletionFrame {
    pub context: String,
    pub epoch: u64,
    pub author: String,
    pub payload_b64: String,
    pub signature: String,
}

impl DeletionFrame {
    pub fn input(&self) -> Result<Vec<u8>, String> {
        transcript(
            b"mosh-deletion-frame-v1\0",
            &(&self.context, self.epoch, &self.author, &self.payload_b64),
        )
    }

    pub fn verify(&self, context: &str) -> Result<(), String> {
        if self.context != context || self.payload_b64.len() > 60000 {
            return Err("invalid deletion frame".into());
        }
        verify_signature(&self.author, &self.signature, &self.input()?)
    }
}

fn transcript(context: &[u8], value: &impl Serialize) -> Result<Vec<u8>, String> {
    let mut bytes = context.to_vec();
    bytes.extend(serde_json::to_vec(value).map_err(|e| e.to_string())?);
    Ok(bytes)
}
