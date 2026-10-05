use super::{
    invalid,
    types::{DeviceMessage, Result},
    MAX_PACKET_BYTES,
};
use crate::device_link::{
    identity::DeviceIdentity,
    roster::{public_key, DeviceRoster},
    types::DeviceDescriptor,
};
use ed25519_dalek::{Signature, Signer};
use serde::{Deserialize, Serialize};

const CLAIM_CONTEXT: &[u8] = b"mosh-dm-client-v1\0";
const PACKET_CONTEXT: &[u8] = b"mosh-dm-admission-v1\0";
const MAX_DISPLAY_NAME_BYTES: usize = 256;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct IdentityClaim {
    pub session_id: String,
    pub roster: DeviceRoster,
    pub device_id: String,
    pub mls_signer: String,
    pub display_name: String,
    signature: String,
}

impl IdentityClaim {
    pub fn create(
        identity: &DeviceIdentity,
        session: &str,
        signer: &[u8],
        name: &str,
    ) -> Result<Self> {
        Self::create_with_roster(identity, identity.roster(), session, signer, name)
    }

    pub fn create_with_roster(
        identity: &DeviceIdentity,
        roster: &DeviceRoster,
        session: &str,
        signer: &[u8],
        name: &str,
    ) -> Result<Self> {
        if !(roster.extends(identity.roster()).map_err(|_| invalid())?
            || identity.roster().extends(roster).map_err(|_| invalid())?)
            || !identity
                .roster()
                .devices()
                .map_err(|_| invalid())?
                .contains(identity.device())
            || !roster
                .devices()
                .map_err(|_| invalid())?
                .contains(identity.device())
        {
            return Err(invalid());
        }
        let mut claim = Self {
            session_id: session.into(),
            roster: roster.clone(),
            device_id: identity.device().device_id.clone(),
            mls_signer: hex::encode(signer),
            display_name: name.into(),
            signature: String::new(),
        };
        claim.signature = hex::encode(identity.key().sign(&claim.bytes()?).to_bytes());
        Ok(claim)
    }

    fn bytes(&self) -> Result<Vec<u8>> {
        let mut bytes = CLAIM_CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(
                &self.session_id,
                &self.roster,
                &self.device_id,
                &self.mls_signer,
                &self.display_name,
            ))
            .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }

    pub fn device(&self) -> Result<DeviceDescriptor> {
        self.roster
            .devices()
            .map_err(|_| invalid())?
            .into_iter()
            .find(|device| device.device_id == self.device_id)
            .ok_or_else(invalid)
    }

    pub fn verify(&self, session: &str) -> Result<()> {
        if self.session_id != session
            || self.display_name.is_empty()
            || self.display_name.len() > MAX_DISPLAY_NAME_BYTES
        {
            return Err(invalid());
        }
        public_key(&self.mls_signer).map_err(|_| invalid())?;
        verify(
            &self.device()?.signing_public_key,
            &self.signature,
            &self.bytes()?,
        )
    }
}

#[derive(Serialize, Deserialize)]
pub(super) struct DevicePacket {
    pub roster: DeviceRoster,
    pub sender: String,
    pub recipient: String,
    pub message: DeviceMessage,
    signature: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    history_metadata: Option<super::history_metadata::HistoryMetadata>,
}

impl DevicePacket {
    pub fn fits_stream(identity: &DeviceIdentity, peer: &str, message: DeviceMessage) -> bool {
        Self::seal(identity, peer, message)
            .ok()
            .and_then(|packet| {
                crate::stream_transport::frame_for_channel(super::DEVICE_CHANNEL, &packet)
            })
            .is_some_and(|frame| frame.len() <= 64 * 1024)
    }

    pub fn seal(
        identity: &DeviceIdentity,
        recipient: &str,
        mut message: DeviceMessage,
    ) -> Result<Vec<u8>> {
        let metadata = super::history_metadata::HistoryMetadata::detach(&mut message);
        let mut packet = Self {
            roster: identity.roster().clone(),
            sender: identity.device().device_id.clone(),
            recipient: recipient.into(),
            message,
            signature: String::new(),
            history_metadata: None,
        };
        packet.signature = hex::encode(identity.key().sign(&packet.bytes()?).to_bytes());
        if let Some(mut metadata) = metadata {
            metadata.sign(identity, &packet.signature)?;
            packet.history_metadata = Some(metadata);
        }
        let bytes = serde_json::to_vec(&packet).map_err(|_| invalid())?;
        if bytes.len() > MAX_PACKET_BYTES {
            return Err(invalid());
        }
        Ok(bytes)
    }

    pub fn open(bytes: &[u8], recipient: &str) -> Result<Self> {
        if bytes.len() > MAX_PACKET_BYTES {
            return Err(invalid());
        }
        let mut packet: Self = serde_json::from_slice(bytes).map_err(|_| invalid())?;
        if packet.recipient != recipient {
            return Err(invalid());
        }
        verify(
            &packet.device()?.signing_public_key,
            &packet.signature,
            &packet.bytes()?,
        )?;
        if let Some(metadata) = packet.history_metadata.take() {
            let key = packet.device()?.signing_public_key;
            metadata.restore(&mut packet.message, &key, &packet.signature)?;
        }
        Ok(packet)
    }

    pub fn device(&self) -> Result<DeviceDescriptor> {
        self.roster
            .devices()
            .map_err(|_| invalid())?
            .into_iter()
            .find(|device| device.device_id == self.sender)
            .ok_or_else(invalid)
    }

    fn bytes(&self) -> Result<Vec<u8>> {
        let mut bytes = PACKET_CONTEXT.to_vec();
        bytes.extend(
            serde_json::to_vec(&(&self.roster, &self.sender, &self.recipient, &self.message))
                .map_err(|_| invalid())?,
        );
        Ok(bytes)
    }
}

pub(super) fn verify(key: &str, signature: &str, bytes: &[u8]) -> Result<()> {
    let signature = hex::decode(signature).map_err(|_| invalid())?;
    let signature = Signature::from_slice(&signature).map_err(|_| invalid())?;
    public_key(key)
        .map_err(|_| invalid())?
        .verify_strict(bytes, &signature)
        .map_err(|_| invalid())
}
