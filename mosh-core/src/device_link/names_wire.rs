//! Account metadata uses Moss's encrypted directed stream, never gossip.
use super::identity::DeviceIdentity;
use super::roster::{invalid, public_key};
use super::types::{DeviceDescriptor, Result};
use crate::chat_names::NameRecord;
use ed25519_dalek::{Signature, Signer};
use serde::{Deserialize, Serialize};

pub(crate) const PREFIX: &[u8] = b"mosh-chat-names-v2\0";

#[derive(Serialize, Deserialize)]
pub(super) enum NameMessage {
    Request {
        after: Option<String>,
        request_id: [u8; 16],
    },
    Batch {
        records: Vec<NameRecord>,
        next: Option<String>,
        request_id: [u8; 16],
    },
    Saved {
        digest: String,
    },
}

#[derive(Serialize, Deserialize)]
struct Packet {
    user: String,
    sender: String,
    recipient: String,
    roster_hash: String,
    message: NameMessage,
    signature: String,
}

impl Packet {
    fn signing_input(&self) -> Result<Vec<u8>> {
        let mut bytes = PREFIX.to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.user,
                &self.sender,
                &self.recipient,
                &self.roster_hash,
                &self.message,
            ))
            .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }
}

pub(super) fn seal(
    identity: &DeviceIdentity,
    recipient: &str,
    message: NameMessage,
) -> Result<Vec<u8>> {
    if identity.revoked()?
        || !identity
            .roster()
            .devices()?
            .iter()
            .any(|d| d.device_id == recipient)
    {
        return Err(invalid());
    }
    let mut packet = Packet {
        user: identity.roster().user_id(),
        sender: identity.device().device_id.clone(),
        recipient: recipient.into(),
        roster_hash: identity.roster().digest()?,
        message,
        signature: String::new(),
    };
    packet.signature = hex::encode(identity.key().sign(&packet.signing_input()?).to_bytes());
    let mut bytes = PREFIX.to_vec();
    bytes.extend(serde_json::to_vec(&packet).map_err(|_| invalid())?);
    if bytes.len() > super::wire::MAX_PACKET_BYTES {
        return Err(invalid());
    }
    Ok(bytes)
}

pub(super) fn open(
    identity: &DeviceIdentity,
    bytes: &[u8],
) -> Result<(DeviceDescriptor, NameMessage)> {
    if bytes.len() > super::wire::MAX_PACKET_BYTES || identity.revoked()? {
        return Err(invalid());
    }
    let packet: Packet = serde_json::from_slice(bytes.strip_prefix(PREFIX).ok_or_else(invalid)?)
        .map_err(|_| invalid())?;
    if packet.user != identity.roster().user_id()
        || packet.recipient != identity.device().device_id
        || packet.roster_hash != identity.roster().digest()?
    {
        return Err(invalid());
    }
    let sender = identity
        .roster()
        .devices()?
        .into_iter()
        .find(|d| d.device_id == packet.sender && d.device_id != packet.recipient)
        .ok_or_else(invalid)?;
    let signature = hex::decode(&packet.signature).map_err(|_| invalid())?;
    public_key(&sender.signing_public_key)?
        .verify_strict(
            &packet.signing_input()?,
            &Signature::from_slice(&signature).map_err(|_| invalid())?,
        )
        .map_err(|_| invalid())?;
    Ok((sender, packet.message))
}
